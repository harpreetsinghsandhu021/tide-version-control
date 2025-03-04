require "zlib"
require_relative "./numbers"
require_relative "./expander"

module Pack
  # The Reader class is responsible for reading and parsing Git pack files.
  # Pack files are binary files that contain compressed objects in Git's database.
  # This class handles the reading of headers, parsing of individual records,
  # and decompression of zlib-compressed content.
  class Reader 
    InvalidPack = Class.new(StandardError)
    attr_reader :count
    
    # Initialize a new Reader with an input stream
    # @param input [IO] The input stream to read from
    def initialize(input)
      # Store the input stream (usually a file) for reading pack data
      @input = input
    end

    # Reads and validates the pack file header
    # The header consists of:
    # - 4-byte signature ('PACK')
    # - 4-byte version number
    # - 4-byte number of objects
    # Raises InvalidPack if the signature or version is incorrect
    def read_header 
      # Read the fixed-size header (12 bytes) from the input stream
      data = @input.read(HEADER_SIZE)
      # Unpack the binary data into signature (4 bytes), version (4 bytes), and object count (4 bytes)
      signature, version, @count = data.unpack(HEADER_FORMAT)

      # Verify that the file starts with the expected 'PACK' signature
      if signature != SIGNATURE
        raise InvalidPack, "bad pack signature: #{ signature }"
      end

      # Ensure we're reading a supported pack file version
      if version != VERSION 
        raise InvalidPack, "unsuppported pack version: #{ version }"
      end
    end

    # Reads a single record from the pack file
    # A record consists of:
    # 1. A header containing the type and size
    # 2. The zlib-compressed object data
    # @return [Record] A new Record instance with type and decompressed data
    def read_record
      # First read the type and size from the record header
      type, _ = read_record_header


      case type
      when COMMIT, TREE, BLOB
        # Create a new Record object with:
        # - The type looked up from TYPE_CODES mapping
        # - The decompressed object data from the zlib stream
        Record.new(TYPE_CODES.key(type), read_zlib_stream) 
     
      when REF_DELTA
        read_ref_delta
      when OFS_DELTA
        read_ofs_delta
      end
    end

    # Reads and parses a record header using variable-length encoding
    # The header contains:
    # - Object type (3 bits)
    # - Size information (variable-length encoding)
    # @return [Array] Returns an array containing [type, size]
    def read_record_header
      # Read a variable-length integer from the input
      # Returns both the first byte and the complete size value
      byte, size = Numbers::VarIntLE.read(@input, 4)
      # Extract the type from the first byte:
      # Right shift by 4 bits and mask with 0x7 to get 3-bit type
      type = (byte >> 4) & 0x7

      # Return both type and size for further processing
      [type, size]
    end

    # Reads and decompresses a zlib-compressed stream of data
    # Uses a streaming approach to handle large objects efficiently:
    # 1. Creates a new zlib inflater
    # 2. Reads data in chunks of 256 bytes
    # 3. Decompresses data on the fly
    # 4. Adjusts file pointer position based on actual bytes consumed
    # @return [String] The decompressed data
    def read_zlib_stream
      # Create a new zlib decompression stream
      stream = Zlib::Inflate.new
      # Buffer to store the decompressed output
      string = ""
      # Track total bytes read for seeking purposes
      total = 0

      # Continue reading until the entire compressed stream is processed
      until stream.finished?
        # Read a chunk of compressed data (256 bytes at a time)
        data = @input.read_nonblock(256)
        # Add the chunk size to our total bytes read
        total += data.bytesize

        # Decompress this chunk and append to our result string
        string.concat(stream.inflate(data))
      end

      # Adjust the file pointer to account for any unused bytes
      # stream.total_in gives us the actual bytes consumed by zlib
      # total gives us how many bytes we read
      # The difference needs to be seeked backwards
      @input.seek(stream.total_in - total, IO::SEEK_CUR)
      # Return the fully decompressed data
      string
    end

    def read_ref_delta
      base_oid = @input.read(20).unpack("H40").first
      RefDelta.new(base_oid, read_zlib_stream)
    end

    def read_ofs_delta
      offset = Numbers::VarIntBE.read(@input)
      OfsDelta.new(offset, read_zlib_stream)
    end

    def read_info
      type, size = read_record_header

      case type
      when COMMIT, TREE, BLOB
        Record.new(TYPE_CODES.key(type), size)

      when REF_DELTA
        delta = read_ref_delta
        size = Expander.new(delta.delta_data).target_size

        RefDelta.new(delta.base_oid, size)
      end
    end

  end
end