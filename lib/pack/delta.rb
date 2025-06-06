require_relative "./numbers"
require_relative "./xdelta"

module Pack
  class Delta 
    
    Copy = Struct.new(:offset, :size) do 

      # Returns a binary string that can be written to a file.
      def to_s
        # size << 32 | offset - This combines the size and offset values into a single number:
        # size << 32 shifts the size value left by 32 bits
        # | offset then combines it with the offset using a bitwise OR
        # The result is a 56-bit number with size in the high 24 bits and offset in the low 32 bits
        bytes = Numbers::PackedInt56LE.write(size << 32 | offset)

        # This sets the most significant bit of the header byte:
        # 0x80 is binary 10000000
        # This marks the operation as a Copy (vs. an Insert)
        bytes[0] |= 0x80

        # This converts the array of bytes into a binary string.
        bytes.pack("C*")
      end  

      def self.parse(input, byte)
        value = Numbers::PackedInt56LE.read(input, byte)
        offset = value & 0xffffffff
        size = value >> 32

        Copy.new(offset, size)
      end
    end

    Insert = Struct.new(:data) do 
      def to_s
        [data.bytesize, data].pack("Ca")
      end

      def self.parse(input, byte)
        Insert.new(input.read(byte))
      end
    end

    def initialize(source, target)
      @base = source.entry
      @data = sizeof(source) + sizeof(target)

      source.delta_index ||= XDelta.create_index(source.data)

      delta = source.delta_index.compress(target.data)
      delta.each { |op| @data.concat(op.to_s) }
    end

    def sizeof(entry)
      # Convert the entry's size into a variable-length integer
      # using 7 bits per byte (VarIntLE format)
      # This is used to create the delta header which stores source/target sizes
      bytes = Numbers::VarIntLE.write(entry.size, 7)

      # Convert the array of bytes into a binary string
      # This format is required for writing to files
      bytes.pack("C*")
    end

  end
end