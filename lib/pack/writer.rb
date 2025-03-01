require "digest/sha1"
require "zlib"

require_relative "./numbers"
require_relative "./entry"
require_relative "./compressor"

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
      compress_objects
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
      # If the entry has a delta, write the delta base entry first.
      write_entry(entry.delta.base) if entry.delta

      # If the entry already has an offset, it has already been written.
      return if entry.offset

      # Set the entry`s offset to the current offset in the packfile.
      entry.offset = @offset

      # Get the object data, either from the delta or from the database. 
      object = entry.delta || @database.load_raw(entry.oid)

      # Construct the packfile header for the entry. 
      # The header is a 4-byte value consisting of:
      #  - 4 bits: packed type (commit, tree etc.)
      #  - 28 bits: packed size (size of the compressed object data)
      header = Numbers::VarIntLE.write(entry.packed_size, 4)
      header[0] |= entry.packed_type << 4

      # Write the header, delta prefix(if any), and compressed object data.
      write(header.pack("C*"))
      write(entry.delta_prefix)
      write(Zlib::Deflate.deflate(object.data, @compression))

      @progress&.tick(@offset)
    end

    def prepare_pack_list(rev_list)
      @pack_list = []
      @progress&.start("Countng objects")

      rev_list.each do |object, path|
        add_to_pack_list(object, path)
        @progress&.tick
      end
      @progress&.stop
    end

    def add_to_pack_list(object, path)
      info = @database.load_info(object.oid)
      @pack_list.push(Entry.new(object.oid, info, path))
    end

    def compress_objects
      compressor = Compressor.new(@database, @progress)
      @pack_list.each { |entry| compressor.add(entry) }

      compressor.build_deltas
    end

  end
end