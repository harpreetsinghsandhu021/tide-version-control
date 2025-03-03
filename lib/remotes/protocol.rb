require_relative "../remotes"

class Remotes
  class Protocol
    
    def initialize(command, input, output, capabilities = [])
      @command = command
      @input = input
      @output = output

      @input.sync = @output.sync = true
      @caps_local = capabilities
      @caps_remote = nil
      @caps_sent = false
    end

    def send_packet(line)
      return @output.write("0000") if line == nil # If the input is nil, this denotes a flush packet.

      line = append_caps(line) # Appends the local capabilities to the message. 
      size = line.bytesize + 5 # Calculate the size i.e byte length of message + 4 bytes for 
                               # the length header +1 for the \n at the end.

      @output.write(size.to_s(16).rjust(4, "0"))
      @output.write(line)
      @output.write("\n")
    end

    # Appends capabilities to the message.
    def append_caps(line)
      return line if @caps_sent

      @caps_sent = true

      sep = (@command == "fetch") ? " " : "\0" # seperator to seperate the capabilities from the message. 
      caps = @caps_local
      caps &= @caps_remote if @caps_remote

      line + sep + caps.join(" ")
    end

    # Reads the message
    def recv_packet
      # Read the first 4 bytes of the packer, this contains the size.
      head = @input.read(4)
      
      # Return the head if it does not match the regex.
      # # The regex matches a string containing 4 hexadecimal characters.
      return head unless /[0-9a-f]{4}/ =~ head

      size = head.to_i(16)
      return nil if size == 0 # Return nil if size is 0, indicating an empty packet. 
      
      # Read the rest of the packet data, excluding the head and trailing newline.
      line = @input.read(size - 4).sub(/\n$/, "")
      # Detect and handle and capability announcements within the packet.
      detect_caps(line)
    end

    # Processes a line from a recieved packet and extracting capability information.
    def detect_caps(line)
      # If capabilities have already been detected remotely, just return the line.
      return line if @caps_remote


      if @command == "upload-pack"
        sep, n = " ", 3 # For "upload-pack", use space as separator and expect 3 parts
      else
        sep, n = "\0", 2 # For other commands, use null character as separator and expect 2 parts
      end

      # Split the line into parts using the determined separator and maximum number of splits
      parts = line.split(sep, n)

      # Extract the capabilities string if the line was split into the expected number of parts
      # If the line doesn't have the expected format, assume an empty capabilities string
      caps = parts.size == n ? parts.pop : ""

       # Split the capabilities string into an array using spaces as delimiters 
      @caps_remote = caps.split(/ +/)

      parts.join(" ")
    end

    # Checks what abilities the other peer supports.
    def capable?(ability)
      @caps_remote&.include?(ability)      
    end

    # Reads messages in a loop until we recieve a particular message
    # that indicates end of a list.
    def recv_until(terminator)
      loop do 
        line = recv_packet
        break if line == terminator
        yield line
      end
    end

  end
end