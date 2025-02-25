class Remotes
  # Regex to parse refspec format: [+]source[:target]
  # + (optional) indicates force update
  # source is required
  # :target is optional
  REFSPEC_FORMAT = /^(\+?)([^:]+):([^:]+)$/

  # Represents a Git refspec which maps source refs to target refs
  # and tracks whether updates should be forced
  Refspec = Struct.new(:source, :target, :forced) do 
    # Converts refspec back to string format
    # Prepends + if forced update, joins source and target with :
    def to_s
      spec = forced ? "+" : ""
      spec + [source, target].join(":")
    end

    # Parses a refspec string into its components
    # @param spec [String] The refspec string to parse
    # @return [Refspec] New Refspec instance with parsed components
    def self.parse(spec)
      # Extract components using regex pattern
      match = REFSPEC_FORMAT.match(spec)
      # Convert source and target to canonical form
      source = Refspec.canonical(match[2])
      # Target defaults to source if not specified
      target = Refspec.canonical(match[4]) || source

      Refspec.new(source, target, match[1] == "+")
    end

    # Converts ref name to its canonical (full) form
    # @param name [String] Reference name to canonicalize
    # @return [String, nil] Full reference path or nil if empty
    def self.canonical(name)
      # Return nil for empty names
      return nil if name.to_s == ""
      # Return as-is if already a valid ref
      return name if !Revision.valid_ref?(name)

      # Get first path component
      first = Pathname.new(name).descend.first
      # Standard Git ref directories
      dirs = [Refs::REFS_DIR, Refs::HEADS_DIR, Refs::REMOTES_DIR]
      # Find matching directory prefix
      prefix = dirs.find { |dir| dir.basename == first }

      # Build full path, defaulting to refs/heads/ if no match
      (prefix&.dirname || Refs::HEADS_DIR).join(name).to_s
    end
  
    # Expands a list of refspecs against available refs
    # @param specs [Array<String>] List of refspec strings
    # @param refs [Array<String>] Available reference names
    # @return [Hash] Mapping of target refs to [source, forced] pairs
    def self.expand(specs, refs)
      # Parse all refspecs
      specs = specs.map { |spec| Refspec.parse(spec) }

      # Build mapping of target refs to source refs and force flags
      specs.reduce({}) do |mappings, spec|
        mappings.merge(spec.match_refs(refs))
      end
    end

    # Matches this refspec against available refs
    # Currently only handles simple (non-wildcard) refspecs
    def match_refs(refs)
      # Only handle literal (non-wildcard) refs for now
      return { target => [source, forced]} if !source.to_s.include?("*")
    end

  end

end