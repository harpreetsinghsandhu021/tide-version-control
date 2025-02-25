require "digest/sha1"
require "zlib"

require_relative "./numbers"

module Pack
  class Writer


    Entry = Struct.new(:oid, :type)

    def initialize(output, database, options={})
      @output = output
      @digest = Digest::SHA1.new
      @database = database

      @compression = options.fetch(:compression, Zlib::DEFAULT_COMPRESSION)
      @progress = options[:progress]
      @offset = 0
    end

    private

    def write(data)
      @output.write(data)
      @digest.update(data)
      @offset += data.bytesize
    end
    
    def write_objects(rev_list)
      prepare_pack_list(rev_list)
      write_header
      write_entries
      @output.write(@digest.digest)
    end

    def prepare_pack_list(rev_list)
      @pack_list = []

      @progress&.start("Counting objects")

      rev_list.each do |object, path|
        add_to_pack_list(object, path)
        @progress&.tick
      end

      @progress&.stop
    end

    def add_to_pack_list(object)
      case object
      when Database::Commit
        @pack_list.push(Entry.new(object.oid, COMMIT))
      when Database::Entry
        type = object.tree? ? TREE : BLOB
        @pack_list.push(Entry.new(object.oid, type))
      end
    end

    def write_header
      header = [SIGNATURE, VERSION, @pack_list.size].pack(HEADER_FORMAT)
      write(header)
    end

    def write_entries

      count = @pack_list.size
      @progress&.start("Writing objects", count) if @output != STDOUT

      @pack_list.each { |entry| write_entry(entry) }
      @progress&.stop
    end

    # Writes a Git object entry to the packfile.
    def write_entry(entry)
      object = @database.load_raw(entry.oid) # Load the raw object data. 
      header = Numbers::VarIntLE.write(object.size) # Encode the object`s size using a variable-length integer format. 
     
      # Set the object`s type bits (first 3 bits) in the first byte of the header.
      header[0] |= entry.type << 4

      # Write the header to the packfile after packing it as a string of bytes("C*")
      write(header.pack("C*"))

      # Compress the object`s data using Zlib deflation with the specified compression level.
      # and write compressed data to the packfile.
      write(Zlib::Deflate.deflate(object.data, @compression))

      @progress&.tick(@offset)
    end


  end
end