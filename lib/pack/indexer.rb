require "digest/sha1"
require "zlib"

require_relative "./expander"

module Pack
  class Indexer 

    class PackFile    

      attr_reader :digest

      def initialize(pack_dir, name)
        @file = Tempfile.new(pack_dir, name)
        @digest = Digest::SHA1.new
      end

      def write(data)
        @file.write(data)
        @digest.update(data)
      end

      def move(name)
        @file.write(@digest.digest)
        @file.move(name)
      end
    end
    
    def initialize(database, reader, stream, progress)
      @database = database
      @reader = reader
      @stream = stream
      @progress = progress

      @index = {}
      @pending = Hash.new { |hash, oid| hash[oid] = [] }

      @pack_file = PackFile.new(@database.pack_path, "tmp_pack")
      @index_file = PackFile.new(@database.pack_path, "tmp_idx")
    end

    def process_pack
      # Orchestrates the entire pack processing workflow:
      # 1. Writes pack file header
      # 2. Processes and writes all objects
      # 3. Writes pack checksum
      # 4. Resolves any delta references
      # 5. Generates and writes the index file
      write_header
      write_objects
      write_checksum

      resolve_deltas
      write_index
    end

    def write_header
      # Writes the pack file header with:
      # - SIGNATURE: Magic number identifying this as a pack file
      # - VERSION: Pack file format version
      # - Object count: Total number of objects in this pack
      header = [SIGNATURE, VERSION, @reader.count].pack(HEADER_FORMAT)
      @pack_file.write(header)
    end

    def write_objects
      # Processes all objects in the pack sequentially:
      # - Starts a progress indicator if configured
      # - Indexes each object individually
      # - Updates progress after each object
      # - Stops progress indicator when complete
      @progress&.start("Receiving objects", @reader.count)

      @reader.count.times do 
        index_object
        @progress&.tick(@stream.offset)
      end

      @progress&.stop
    end

    def index_object
      # Processes and indexes a single object:
      # - Captures current stream offset
      # - Reads and captures the object record and raw data
      # - Calculates CRC32 checksum of the raw data
      # - Writes raw data to pack file
      # - For regular objects: Computes object hash and updates index
      # - For delta objects: Adds to pending list for later resolution
      offset = @stream.offset
      record, data = @stream.capture { @reader.read_record }
      crc32 = Zlib.crc32(data)

      @pack_file.write(data)

      case record
      when Record
        oid = @database.hash_object(record)
        @index[oid] = [offset, crc32]
      when RefDelta
        @pending[record.base_oid].push([offset, crc32])
      end
    end

    def write_checksum
      @stream.verify_checksum

      filename = "pack-#{ @pack_file.digest.hexdigest }.pack"
      @pack_file.move(filename)

      path = @database.pack_path.join(filename)
      @pack = File.open(path, File::Constants::RDONLY)
      @reader = Reader.new(@pack)
    end

    def read_record_at(offset)
      @pack.seek(offset)
      @reader.read_record
    end

    def resolve_deltas
      # Resolves all delta references in the pack:
      # 1. Calculates total number of deltas to process
      # 2. Initializes progress tracking for delta resolution
      # 3. Iterates through all base objects in the index
      # 4. For each base object:
      #    - Reads the original record from pack
      #    - Resolves any deltas that depend on it
      # 5. Completes progress tracking
      deltas = @pending.reduce(0) { |n, (_list)| n + list.size }
      @progress&.start("Resolving deltas", deltas)

      @index.to_a.each do |oid,(offset, _)|
        record = read_record_at(offset)
        resolve_delta_base(record, oid)
      end
      @progress&.stop
    end

    def resolve_delta_base(record, oid)
      # Processes all pending deltas for a given base object:
      # 1. Retrieves and removes list of pending deltas for this base OID
      # 2. If no pending deltas exist, returns early
      # 3. Otherwise, processes each pending delta:
      #    - Takes the offset and CRC32 of the delta
      #    - Resolves the delta against its base object
      pending = @pending.delete(oid)
      return if !pending

      pending.each do |offset, crc32|
        resolve_pending(record, offset, crc32)
      end
    end

    def resolve_pending(record, offset, crc32)
      delta = read_record_at(offset)
      data = Expander.expand(record.data, delta.delta_data)
      object = Record.new(record.type, data)
      oid = @database.hash_object(object)

      @index[oid] = [offset, crc32]
      @progress&.tick

      resolve_delta_base(object, oid)
    end

    def write_index
      @object_ids = @index.keys.sort

      write_object_table
      write_crc32
      write_offsets
      write_index_checksum
    end

    # Writes the object table to the index file.
    # The object table lists all object IDs in the packfile, sorted by
    # their object ID, and provides an index to locate each object in
    # the packfile.
    def write_object_table
      # Write the object table header
      # The header consists of:
      #  - 4 bytes: signature (IDX_SIGNATURE)
      #  - 4 bytes: version (VERSION)
      header = [IDX_SIGNATURE, VERSION].pack("N2")
      @index_file.write(header)

      # Calculate the cumulative object counts for each byte value.
      counts = Array.new(256, 0) 
      total = 0

      # Iterate over each object ID(oid) and increment the count corresponding
      # to the first byte of the object ID
      @object_ids.each { |oid| counts[oid[0..1].to_i(16)] += 1 }

      # Write the cumulative object counts to the index file.
      # we iterate over the counts array and write the cumulative total for each 
      # byte value. This allows for quickly seeking to a specific object ID in the packfile.
      counts.each do |count|
        total += count
        @index_file.write([total].pack("N"))
      end

      # Write the objects IDs to the index file.
      # We iterate over the sorted object IDs and write each one to the index file.
      # The Object IDs are packed as 40 character hexadecimal string.
      @object_ids.each do |oid|
        @index_file.write([oid].pack("h40"))
      end
    end

    def write_crc32
      @object_ids.each do |oid|
        crc32 = @index[oid].last
        @index_file.write([crc32].pack("N"))
      end
    end

    # Writes the object offsets to the index file.
    # Object offsets indicate the position of each object in the packfile.
    # If an offset exceeds IDX_MAX_OFFSET (2**32 - 1), it's written as a 32-bit
    # index into a separate table of large offsets.
    def write_offsets
      large_offsets = [] # will store offsets exceeding IDX_MAX_OFFSET.

      @object_ids.each do |oid|
        # Get the offset of the object from the index.
        offset = @index[oid].first

        # If the offset is larger than the maximum allowed,
        if offset > IDX_MAX_OFFSET
          # Add the large offset to the `large_offsets` array.
          large_offsets.push(offset)
          # Encode the offset as an index into the `large_offsets` array.
          offset = IDX_MAX_OFFSET | (large_offsets.size - 1)
        end

        # Write the encoded offset to the index file as a 32-bit integer.
        @index_file.write([offset].pack("N"))
      end

      # Write the large offsets to the index file.
      large_offsets.each do |offset|
        # Write each large offset as a 64-bit integer in big-endian byte order.
        @index_file.write([offset].pack("Q>"))
      end
    end

    # Writes the packfile checksum to the index file and renames the index file.
    def write_index_checksum
      # Calculate the SHA-1 checksum of the entire packfile.
      pack_digest = @pack_file.digest

      # Write the checksum to the index file. 
      # This checksum is used to verify the integrity of the packfile.
      @index_file.write(pack_digest.digest)

      # Rename the index file to include the packfile's SHA-1 checksum.
      filename = "pack-#{ pack_digest.hexdigest }.idx"
      @index_file.move(filename)
    end

  end
end