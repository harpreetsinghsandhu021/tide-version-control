require_relative "./window"
require_relative "./delta"

module Pack
  class Compressor 
    
    OBJECT_SIZE = 50..0x20000000 # range of entry size i.e 50 bytes to 512 megabytes
    WINDOW_SIZE = 8
    MAX_DEPTH = 50

    def initialize(database, progress)
      @database = database
      @window = Window.new(WINDOW_SIZE)
      @progress = progress
      @objects = []
    end

    def add(entry)
      return if !OBJECT_SIZE.include?(entry.size)
      @objects.push(entry)
    end

    def build_deltas
      @progress&.start("Compressing objects", @objects.size)
      @objects.sort_by!(&:sort_key)

      @objects.reverse_each do |entry|
        build_delta(entry)
        @progress&.tick
      end

      @progress&.stop
    end

    def build_delta(entry)
      object = @database.load_raw(entry.oid)
      target = @window.add(entry, object.data)

      @window.each { |source| try_delta(source, target)}
    end

    # Attempts to combine two entries in a delta pair.
    def try_delta(source, target)
      return if source.type != target.type
      return if source.depth > MAX_DEPTH

      max_size = max_size_heuristic(source, target)
      return if !compatible_sizes?(source, target, max_size)

      delta = Delta.new(source, target)
      size = target.entry.packed_size

      return if delta.size > size
      return if delta.size == size && delta.base.depth + 1 >= target.depth

      target.entry.assign_delta(delta)
    end

    # Calculate the maximum allowed size for a delta to be considered worthwhile.
    def max_size_heuristic(source, target)
      # Check if the target object(the newer version) already has a delta.
      if target.delta
        # If the target already has a delta, the new delta must be smaller than the existing one.
        max_size = target.delta.size # Use the existinf delta`s size as the starting point. 
        ref_depth = target.depth # The reference depth is the target`s depth in the history. 
      else
        # If the target does not have a delta, calculate a base threshold.
        max_size = target.size / 2 - 20 # Start with half the target`s size minus some overhead. 
        ref_depth = 1 # Since there`s no existing delta, the reference depth is 1. 
      end

      # Adjust the threshold based on the depth difference between source and target.
      # This encourages shorter delta chains by being more lenient on size when the source is
      # closer to the target.
      max_size * (MAX_DEPTH  - source.depth) / (MAX_DEPTH + 1 - ref_depth)
    end

    def compatible_sizes?(source, target, max_size)
      size_diff = [target.size - source.size, 0].max

      return false if max_size == 0
      return false if size_diff >=  max_size
      return false if target.size < source.size / 32

      true
    end

  end
end