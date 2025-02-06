require "digest/sha1"

class Index
  # Handles SHA1 checksum calculation and verification for index files
  # Similar to Git's index file integrity checking mechanism
  class Checksum
    
    # Custom error for unexpected end-of-file conditions
    EndOfFile = Class.new(StandardError)

    # Size of SHA1 checksum in bytes
    CHECKSUM_SIZE = 20

    # Initialize a new checksum calculator
    # @param file [File] File handle for reading/writing
    def initialize(file)
      @file = file
      @digest = Digest::SHA1.new
    end

    # Read data while updating running checksum
    # @param size [Integer] Number of bytes to read
    # @return [String] Read data
    # @raise [EndOfFile] If EOF reached before size bytes read
    def read(size)
      data = @file.read(size)
      
      unless data.bytesize == size
        raise EndOfFile, "Unexpected end of file while reading index"
      end

      @digest.update(data)
      data
    end

    # Verify stored checksum against calculated value
    # @raise [Invalid] If checksums don't match
    def verify_checksum
      sum = @file.read(CHECKSUM_SIZE)

      if sum != @digest.digest
        raise Invalid, "Checksum does not match value stored on disk"
      end
    end

    # Write data while updating running checksum
    # @param data [String] Data to write
    def write(data)
      @file.write(data)
      @digest.update(data)
    end

    # Write final checksum to file
    def write_checksum
      @file.write(@digest.digest)
    end
  end
end