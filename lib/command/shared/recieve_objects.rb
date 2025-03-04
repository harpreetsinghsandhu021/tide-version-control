require_relative "../../pack"
require_relative "../../progress"
require_relative "../../pack/stream"
require_relative "../../pack/reader"
require_relative "../../pack/unpacker"
require_relative "../../pack/indexer"

module Command
  # RecieveObjects module handles the network reception of Git objects
  # by unpacking and storing them from a packfile stream
  module RecieveObjects
    
    UNPACK_LIMIT = 100
    # Receives and stores Git objects from a packed format stream
    # @param prefix [String] Optional prefix for the pack stream (default: "")
    # @details
    # - Creates a Pack::Stream to read incoming packfile data
    # - Uses Pack::Reader to parse the packfile format
    # - Reads pack header and validates format
    # - Processes each object and stores it in the repository
    # - Verifies pack checksum for data integrity
    def recv_packed_objects(unpack_limit=nil,prefix = "")
      # Initialize pack stream reader for incoming data
      stream = Pack::Stream.new(@conn.input, prefix)
      reader = Pack::Reader.new(stream)
      
      # Initialize progress for displaying progrss of downloading process
      progress = Progress.new(@stderr) if @conn.input != STDIN
      
      # Read and validate pack header
      reader.read_header

     factory = select_processor_class(reader, unpack_limit)
     processor = factory.new(repo.database, reader, stream, progress)
     processor.process_pack

     repo.database.reload
    end

    def select_processor_class(reader, unpack_limit)
      unpack_limit ||= transfer_unpack_limit
      
      if unpack_limit and reader.count > unpack_limit
        Pack::Indexer
      else
        Pack::Unpacker
      end
    end
    
    def transfer_unpack_limit
      repo.config.get(["transfer", "unpackLimit"]) || UNPACK_LIMIT
    end
  end
end