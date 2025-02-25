require_relative "../../pack"
require_relative "../../progress"

module Command
  # RecieveObjects module handles the network reception of Git objects
  # by unpacking and storing them from a packfile stream
  module RecieveObjects
    
    # Receives and stores Git objects from a packed format stream
    # @param prefix [String] Optional prefix for the pack stream (default: "")
    # @details
    # - Creates a Pack::Stream to read incoming packfile data
    # - Uses Pack::Reader to parse the packfile format
    # - Reads pack header and validates format
    # - Processes each object and stores it in the repository
    # - Verifies pack checksum for data integrity
    def recv_packed_objects(prefix = "")
      # Initialize pack stream reader for incoming data
      stream = Pack::Stream.new(@conn.input, prefix)
      reader = Pack::Reader.new(stream)
      
      # Initialize progress for displaying progrss of downloading process
      progress = Progress.new(@stderr) if !@conn.input = STDIN
      
      # Read and validate pack header
      reader.read_header

      progress&.start("Unpacking objects", reader.count)
      
      # Process each object in the pack
      reader.count.times do 
        # Capture and store each object record
        record, _ = stream.capture { reader.read_record }
        repo.database.store(record)
        progress&.tick(stream.offset)
      end
      progress&.stop

      # Verify pack integrity using checksum
      stream.verify_checksum
    end

  end
end