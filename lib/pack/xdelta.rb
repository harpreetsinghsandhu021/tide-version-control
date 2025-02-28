module Pack
  class XDelta
    
    BLOCK_SIZE = 16

    def self.create_index(source)
      # Calculate total number of complete blocks in the source
      # by dividing source bytesize by BLOCK_SIZE (16)
      blocks = source.bytesize / BLOCK_SIZE

      # Initialize empty hash to store block slices and their positions
      index = {}

      # Iterate through each block (0 to number of blocks)
      (0..blocks).each do |i|
        # Calculate starting position of current block
        # e.g., block 0 starts at 0, block 1 at 16, block 2 at 32, etc.
        offset = i * BLOCK_SIZE

        # Extract a slice of BLOCK_SIZE bytes from source starting at offset
        # This creates a "rolling window" of 16 bytes
        slice = source.byteslice(offset, BLOCK_SIZE)

        # Initialize empty array for this slice if it doesn't exist
        # This handles duplicate blocks by storing multiple positions
        index[slice] ||= []

        # Store the offset position where this slice was found
        # Multiple positions may exist for identical blocks
        index[slice].push(offset)
      end

      # Create and return new XDelta instance with source and computed index
      XDelta.new(source, index)
    end

    def initialize(source, index)
      @source = source
      @index = index
    end

    def compress(target)
      @target = target
      @offset = 0
      @insert = []
      @ops = []

      generate_ops while @offset < @target.bytesize
      flush_insert

      @ops
    end

    def generate_ops
      m_offset, m_size = longest_match

      return push_insert if m_size == 0

      m_offset, m_size = expand_match(m_offset, m_size)

      flush_insert
      @ops.push(Delta::Copy.new(m_offset, m_size))
    end

    def longest_match
      # Extract a block-sized slice from target at current offset
      slice = @target.byteslice(@offset, BLOCK_SIZE)

      # If this slice doesn't exist in our index, no match found
      # Return [0,0] indicating no matching sequence
      return [0, 0] if !@index.has_key?(slice)

      # Initialize match offset and size to 0
      # These will track the best match found
      m_offset = m_size = 0

      # Check each position where this slice appears in source
      @index[slice].each do |pos|
        # Calculate how many bytes remain in source from this position
        remaining = remaining_bytes(pos)

        # If remaining bytes are less than our best match so far,
        # no point checking this position
        break if remaining <= m_size

        # Find how far the match extends from this position
        s = match_from(pos, remaining)

        # Skip if current best match is longer than this one
        # (s - pos gives length of current match)
        next if m_size >= s - pos

        # We found a better match! Update our tracking variables
        m_offset = pos         # Position in source where match starts
        m_size = s - pos      # Length of the match
      end

      # Return the best match found as [position, length]
      [m_offset, m_size]
    end

    def remaining_bytes(pos)
      source_remaining = @source.bytesize - pos
      target_remaining = @target.bytesize - @offset

      [source_remaining, target_remaining, MAX_COPY_SIZE].min
    end

    def match_from(pos, remaining)
      s, t = pos, @offset

      while remaining > 0 && @source.getbyte(s) == @target.getbyte(t)
        s, t = s + 1, t + 1
        remaining -= 1        
      end
      
      s
    end

    def expand_match(m_offset, m_size)
      while m_offset > 0 && @source.getbyte(m_offset - 1) == @insert.last
        break if m_size == MAX_COPY_SIZE

        @offset -= 1
        m_offset -= 1
        m_size += 1

        @insert.pop
      end

      @offset += m_size

      [m_offset, m_size]
    end

    def push_insert
      @insert.push(@target.getbyte(@offset))
      @offset += 1
      flush_insert(MAX_INSERT_SIZE)
    end

    def flush_insert(size = nil)
      return if size && @insert.size < size
      return if @insert.empty?

      @ops.push(Delta::Insert.new(@insert.pack("C*")))
      @insert = []
    end

  end
end