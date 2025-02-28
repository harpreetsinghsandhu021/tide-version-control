require_relative "./numbers"

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
    end

    Insert = Struct.new(:data) do 
      def to_s
        [data.bytesize, data].pack("Ca")
      end
    end


  end
end