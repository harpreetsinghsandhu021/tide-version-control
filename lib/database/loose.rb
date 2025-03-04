
class Database
  class Loose 
    
    def initialize(pathname)
      @pathname = pathname
    end

    def has?(oid)
      File.file?(object_path(oid))
    end
  
    def load_info(oid)
      type, size, _ = read_object_header(oid, 128)
      Raw.new(type, size)
    end

    # Same as load method, except this skips the work of parsing 
    # the object into a Commit, Tree or Blob. That’s because Pack::Writer just wants to write the
    # serialised object directly to the output stream and doesn’t actually care about its type or internal
    # structure — it’s just a blob of data.So it would be pointless to parse the object only to re-serialise it
    def load_raw(oid)
      type, size, scanner = read_object_header(oid)
      Raw.new(type, size, scanner.rest)
    end

    def prefix_match(name)
      dirname = object_path(name).dirname
      oids = Dir.entries(dirname).map do |filename|
        "#{ dirname.basename }#{ filename }"
      end
      oids.select { |oid| oid.start_with?(name) }
    rescue Errno::ENOENT
      []
    end


    # Writes an object to the database using git's content-addressable storage scheme
    # Objects are stored in subdirectories based on first 2 characters of their hash
    # @param oid [String] Object ID (SHA1 hash)
    # @param content [String] Object content to write
    def write_object(oid, content)
      # Split the oid into directory prefix (first 2 chars) and filename (remaining chars)
      path = object_path(oid)
      return if File.exist?(path)
      
      file = TempFile.new(path.dirname, "tmp_obj")
      file.write(Zlib::Deflate.deflate(content, Zlib::BEST_SPEED))
      file.move(path.basename)
      
    end

    private

    def object_path(oid)
      @pathname.join(oid[0..1].to_s, oid[2..-1].to_s)
    end

    def read_object_header(oid, read_bytes = nil)
      path = object_path(oid)
  
      # Reads the object from disk and then decompress it using zlib
      data = Zlib::Inflate.inflate(File.read(path, read_bytes))
      # creates a StringScanner instance which can be used for parsing data
      scanner = StringScanner.new(data)
   
      # use stringscanner to scan_until we find a space, giving us the object`s type
      type = scanner.scan_until(/ /).strip
      # scan_until we find a null byte, giving us the size
      size = scanner.scan_until(/\0/)[0..-2].to_i
  
      [type, size, scanner]
   
    end

  end
end