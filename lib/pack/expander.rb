require "stringio"

require_relative "./numbers"
require_relative "./delta"


module Pack
  class Expander 
    
    attr_reader :source_size, :target_size

    def self.expand(source, delta)
      Expander.new(delta).expand(source)
    end

    def initialize(delta)
      @delta = StringIO.new(delta)

      @source_size = read_size
      @target_size = read_size
    end

    def read_size
      Numbers::VarIntLE.read(@delta, 7)[1]
    end


    def expand(source)
      check_size(source, @source_size)
      target = ""

      until @delta.eof?
        byte = @delta.readbyte

        if byte < 0x80
          insert = Delta::Insert.parse(@delta, byte)
          target.concat(insert.data)
        else
          copy = Delta::Copy.parse(@delta, byte)
          target.concat(source.byteslice(copy.offset, copy.size))
        end
      end

      check_size(target, @target_size)
      target
    end

    # Checks the sizes of the strings against the sizes recorded at the beginning
    # of the delta. If they disagree, an error is thrown.
    def check_size(buffer, size)
      raise "failed to apply delta" if buffer.bytesize != size
    end

  end
end