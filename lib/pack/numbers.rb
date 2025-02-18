module Pack
  module Numbers
    
    module VarIntLE
      # This module provides a method for encoding integers 
      # using a variable-length, little-endian format.

      # Writes an integer 'value' to a byte array using a variable-length,
      # little-endian encoding scheme. 
      # This is useful for representing numbers efficiently, especially 
      # when dealing with values that are often small.
      #
      # Arguments:
      #   value: The integer to be encoded.
      #
      # Returns:
      #   bytes: An array of bytes representing the encoded integer.
      

      def self.write(value)
        bytes = []
        mask = 0xf # Bitmask to extract the least significant 4 digits.

        shift = 4 # Set the initial bit shift amount to 4.

        until value <= mask
          # First, value & mask: This performs a bitwise AND between
          # value and mask, keeping only the bits that are set in both
          # numbers
          # Then, 0x80 | (value & mask): This takes the result from step
          # 1 and performs a bitwise OR with 0x80 (binary: 10000000)
          # 0x80 sets the highest bit to 1
          # The result will always have its highest bit set, plus whatever
          #  bits survived from the AND operation
          # Finally, bytes << [result from step 2]: This is a left shift
          # operation where bytes is being shifted by the amount specified
          #  by the result from step 2
          bytes << (0x80 | value & mask)

          value >>= shift # Right shift "value" by "shift" bits to process the next
                          # set of bits.
                          
          # Update the mask and shift for subsequent bytes (7 bits per byte).
          mask, shift = 0x7f, 7
        end

         # Add the final byte (which has its most significant bit set to 0)
        bytes + [value]
      end

      # Reads a variable-length encoded integer from an input stream.
      # It's based on a format where the most significant bit of each byte
      # indicates if there are more bytes to follow.
      # 
      # Returns a tuple: [first_byte, decoded_value]
      def self.read(input)
        # Read the first byte from the input stream
        first = input.readByte 

        # Extract the lower 4 bits of the first byte. This gives us the initial value.
        value = first & 0xf  

        # Initialize the bit shift amount. We start by shifting 4 bits 
        # because the first byte only uses the lower 4 bits for the value.
        shift = 4 

        # Store the current byte being processed (starts with the first byte)
        byte = first 

        # Keep looping until we encounter a byte where the most significant bit is 0.
        # This indicates the end of the encoded value. 
        until byte < 0x80 
          # Read the next byte from the input stream
          byte = input.readbyte 
          
          # Extract the lower 7 bits of the current byte.
          # Shift these bits left by the current 'shift' amount 
          # to align them properly with the previously accumulated value.
          # Use bitwise OR (|=) to combine the shifted bits with the 'value'.
          value |= (byte & 0x7f) << shift  
          
          # Increment the shift amount by 7 for the next iteration
          # as each subsequent byte contributes 7 bits to the final value. 
          shift += 7 
        end

        # Return the first byte and the fully decoded integer value.
        [first, value] 
      end

    end
  end
end