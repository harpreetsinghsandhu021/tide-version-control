
class Remotes

  REFSPEC_FORMAT = /^(\+?)([^:]+):([^:]+)$/

  Refspec = Struct.new(:source, :target, :forced) do 
    def to_s
      spec = forced ? "+" : ""
      spec + [source, target].join(":")
    end

    def self.parse(spec)
      match = REFSPEC_FORMAT.match(spec)
      Refspec.new(match[2], match[3], match[1] == "+")
    end
  
    def self.expand(specs, refs)
      specs = specs.map { |spec| Refspec.parse(spec) }

      specs.reduce({}) do |mappings, spec|
        mappings.merge(spec.match_refs(refs))
      end
    end

    def match_refs(refs)
      return { target => [source, forced]} if !source.to_s.include?("*")
    end

  end

end