require "digest/sha1"

module Pack
  class Stream 

    attr_reader :digest, :offset
    
    def initialize(input, buffer = "")
      @input = input
      @digest = Digest::SHA1.new
      @offset = 0

      @buffer = new_byte_string.concat(buffer) # Stores data that`s already been fetched from the underlying IO.
      @capture = nil # Holds data for the object being parsed, any access can be moved to @buffer for later.
    end

    def new_byte_string
      String.new("", :encoding => Encoding::ASCII_8BIT)
    end

    def read(size)
      # Use read_buffered to get 'size' bytes of data, using blocking mode
      # This will first try to read from the internal buffer,
      # then from the input stream if needed
      data = read_buffered(size)

      # Update the stream's state (digest, offset, and capture buffer)
      # This maintains consistency of the stream's internal state
      update_state(data)

      # Return the read data to the caller
      data
    end

    def read_nonblock(size)
      # Similar to read, but uses non-blocking mode in read_buffered
      # This means it will raise EWOULDBLOCK if no data is immediately available
      data = read_buffered(size, false)

      # Update the stream's state just like in regular read
      # This ensures consistent state management regardless of read mode
      update_state(data)

      # Return the read data to the caller
      # May be less than requested size in non-blocking mode
      data
    end

    def readbyte
      read(1).bytes.first
    end

     # Captures all data read while the block is executed.
     def capture 
      # Creates a new empty string to store the captured data.
      @capture = new_byte_string

      # Execute the code block passed to the method.
      result = [yield, @capture]

      # Updates the SHA-1 checksum with the captured data.
      @digest.update(@capture)

      # Clears the captured data buffer.
      @capture = nil

      result
     end

       
    def seek(amount, whence = IO::SEEK_SET)
      # Only process negative seek amounts (backwards seeking)
      return if !(amount < 0)
      
      # Remove the specified amount of data from the end of capture buffer
      # and return it as a new string
      data = @capture.slice!(amount..-1)
      
      # Add the removed data to the beginning of the main buffer
      # This allows us to "rewind" and read this data again later
      @buffer.prepend(data)
      
      # Update the current position in the stream
      # This maintains accurate tracking of our location
      @offset += amount
    end

    def verify_checksum
      unless read_buffered(20) == @digest.digest
        raise InvalidPack, "Checksum does not match value read from pack"
      end
    end
    
    private


  
    def read_buffered(size, block = true)
      # First attempt to read data from our internal buffer
      # This removes and returns up to 'size' bytes from the buffer
      from_buf = @buffer.slice!(0, size)
      
      # Calculate how many more bytes we need after reading from buffer
      needed = size - from_buf.bytesize
      
      # Read the remaining needed bytes from the input stream
      # Use blocking or non-blocking read based on the 'block' parameter
      from_io = block ? @input.read(needed) : @input.read_nonblock(needed)

      # Combine the data from buffer and input stream
      # Converting input to string to handle nil case safely
      from_buf.concat(from_io.to_s)

    rescue EOFError, Errno::EWOULDBLOCK
      # Return whatever we managed to read if we hit EOF
      # or would block in non-blocking mode
      from_buf
    end


    def update_state(data)
      # Skip updating the digest if we're currently capturing data
      # This prevents double-counting data in the SHA-1 checksum
      # when we're in capture mode (@capture is not nil)
      @digest.update(data) if !@capture

      # Update the current offset by adding the size of the new data
      # This keeps track of our position in the overall stream
      @offset += data.bytesize

      # If we're in capture mode (i.e., @capture exists),
      # append the new data to the capture buffer
      # This is used when we need to temporarily store data
      # for processing or verification
      @capture&.concat(data)
    end

  
   

  end
end