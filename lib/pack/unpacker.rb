require_relative "./expander"

module Pack
  class Unpacker
    
    def initialize(databse, reader, stream, progress)
      @database = databse
      @reader = reader
      @stream = stream
      @progress = progress
    end

    def process_pack
      @progress&.start("Unpacking objects", @reader.count)
      
      # Process each object in the pack
      @reader.count.times do 
       process_record
       @progress&.tick(@stream.offset)
      end
      @progress&.stop

      # Verify pack integrity using checksum
      @stream.verify_checksum
    end

    def process_record
       # Capture and store each object record
       record, _ = @stream.capture { @reader.read_record }
       record = resolve(record)
       @database.store(record)
    end

    def resolve(record)
      # Determine how to handle the record based on its type
      # Record - represents a complete object, return as-is
      # RefDelta - represents a delta that needs to be resolved against its base
      case record
      when Record  then record 
      when RefDelta then resolve_ref_delta(record)
      end
    end

    def resolve_ref_data(record)
      # Resolve a reference delta by:
      # 1. Getting the base object's OID from the delta
      # 2. Getting the delta data that describes changes
      # 3. Passing both to resolve_delta for reconstruction
      resolve_delta(delta.base_oid, delta.delta_data)
    end

    def resolve_delta(oid, delta_data)
      # 1. Load the base object using its OID from the database
      base = @database.load_raw(oid)

      # 2. Apply the delta data to the base object using Expander
      # This reconstructs the target object from base + delta
      data = Expander.expand(base.data, delta_data)

      # 3. Create a new Record with the base object's type
      # and the reconstructed data
      Record.new(base.type, data)
    end

  end
end