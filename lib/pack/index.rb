
module Pack
  class Index 
    
    HEADER_SIZE = 8
    FANOUT_SIZE = 1024

    # These help us find positions to read from in the .idx file
    OID_LAYER = 2
    CRC_LAYER = 3
    OFS_LAYER = 4
    EXT_LAYER = 5

    SIZES = {
      OID_LAYER => 20, 
      CRC_LAYER => 4, 
      OFS_LAYER => 4, 
      EXT_LAYER => 8
    }

    def initialize(input)
      @input = input
      load_fanout_table
    end

    def load_fanout_table
      @input.seek(HEADER_SIZE)
      @fanout = @input.read(FANOUT_SIZE).unpack("N256")
    end

    def oid_offset(oid)
      pos = oid_position(oid)
      return nil if pos < 0

      offset = read_int32(OFS_LAYER, pos)
      return offset if offset < IDX_MAX_OFFSET

      pos = offset & (IDX_MAX_OFFSET - 1)
      @input.seek(offset_for(EXT_LAYER, pos))
      @input.read(8).unpack("Q>").first
    end

    def offset_for(layer, pos)
      offset = HEADER_SIZE + FANOUT_SIZE

      count = @fanout.last

      SIZES.each { |n, size| offset += size * count if n < layer }

      offset + pos * SIZES[layer]
    end

    def read_int32(layer, pos)
      @input.seek(offset_for(layer, pos))
      @input.read(4).unpack("N").first
    end

    def oid_position(oid)
      # Converts the first two digits of the ID to a number.
      # to_i(16) - converts a string representation of a hexadecimal number into 
      # its equivalent integer value.
      prefix = oid[0..1].to_i(16)
      packed = [oid].pack("H40")

      low = prefix == 0 ? 0 : @fanout[prefix - 1]
      high = @fanout[prefix] - 1

      binary_search(packed, low, high)
    end

    # Performs a binary search for a target object ID within a specific layer
    # of the packfile index.
    def binary_search(target, low, high)
      while low <= high
        mid = (low + high) / 2

        # Seek to the object ID at the middle index in the packfile index.
        @input.seek(offset_for(OID_LAYER, mid))
        # Read from the object ID from the packfile index.
        oid = @input.read(20)

        # Compare the read object ID with the target object ID.
        case oid <=> target
        when -1 then low = mid + 1
        when 0 then return mid
        when 1 then high = mid - 1
        end
      end
      
      # If the target object ID is not found, return a negative value
      # # indicating the insertion point.
      -1 - low
    end

    # Takes a partial object ID and have it expanded to a full one, 
    # by matching against the IDs that exist in the database.
    def prefix_match(name)
      pos = oid_position(name)
      return [name] if pos > 0

      @input.seek(offset_for(OID_LAYER, -1 - pos))
      oids = []

      loop do 
        oid = @input.read(20).unpack("H40").first
        return oids if !oid.start_with?(name)
        oids.push(oid)
      end
    end

  end
end