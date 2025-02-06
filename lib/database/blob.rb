class Database
  # Represents a binary large object (blob) in the version control system
  # Similar to Git's blob object type, stores the contents of a file
  class Blob 
    # Object ID (SHA1 hash) of the blob
    # Set after the blob is stored in the database
    attr_accessor :oid
    attr_reader :data
    
    # Initialize a new blob with file content
    # @param data [String] Raw file content to store
    def initialize(data)
      @data = data 
    end
  
    # Returns the object type identifier
    # @return [String] Always returns "blob"
    def type 
      "blob"
    end
    
    # Returns the blob's content
    # @return [String] Raw file content
    def to_s
      @data
    end

    def self.parse(scanner)
      Blob.new(scanner.rest)
    end
  end
end