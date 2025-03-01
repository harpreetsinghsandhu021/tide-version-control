require "forwardable"

module Pack
  class Entry

    extend Forwardable

    def_delegator :@info, :type, :size

    attr_reader :oid, :delta, :depth

    attr_accessor :offset
    
    def initialize(oid, info, path)
      @oid = oid
      @info = info
      @path = path
      @delta = nil
      @depth = 0
    end

    def sort_key
      [packed_type, @path&.basename, @path&.dirname, @info.size]
    end

    def packed_type
      @delta ? REF_DELTA : TYPE_CODES.fetch(@info.type)
    end

    def delta_prefix
      @delta ? [@delta.base.oid].pack("H40") : ""
    end

    def packed_size
      @delta ? @delta.size : @info.size
    end

    def assign_delta(delta)
      @delta = delta
      @depth = delta.base.depth + 1
    end

  end
end