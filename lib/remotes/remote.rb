require_relative "../remotes"

class Remotes

  # Regex to validate and parse refspecs.
  # For example:
  #   "+refs/heads/*:refs/remotes/origin/*" => ["+", "refs/heads/*", "refs/remotes/origin/*"]
  REFSPEC_FORMAT = /^(\+?)([^:]+):([^:]+)$/

  # Define a struct to hold refspec data.
  # source - local branch name, target - remote branch name, forced - force update flag.
  Refspec = Struct.new(:source, :target, :forced) do 
    # Convert a Refspec object back to its string representation.
    # For example: 
    #  Refspec.new("refs/heads/main", "refs/remotes/origin/main", false).to_s => "refs/heads/main:refs/remotes/origin/main"
    #  Refspec.new("refs/heads/feature", "refs/remotes/origin/feature", true).to_s => "+refs/heads/feature:refs/remotes/origin/feature"
    def to_s
      spec = forced ? "+" : "" # Add "+" prefix if forced is true.
      spec + [source, target].join(":") # Join source and target with ":".
    end

    # Parse a refspec string into a Refspec object.
    # For example:
    #   Refspec.parse("+refs/heads/*:refs/remotes/origin/*") => #<struct Refspec source="refs/heads/*", target="refs/remotes/origin/*", forced=true>
    def self.parse(spec)
      match = REFSPEC_FORMAT.match(spec) # Match the spec against the regex.
      Refspec.new(match[2], match[3], match[1] == "+") # Create a new Refspec object with extracted values.
    end
  
    # Expand an array of refspecs and match them against a list of refs.
    # For example:
    #  Refspec.expand(["+main:main", "feature:feature"], ["main", "feature", "develop"]) => {"main"=>["main", true], "feature"=>["feature", false]}
    def self.expand(specs, refs)
      specs = specs.map { |spec| Refspec.parse(spec) } # Parse each spec string into a Refspec object.

      # Iterate over the parsed specs and merge their matched refs into a single hash.
      specs.reduce({}) do |mappings, spec| 
        mappings.merge(spec.match_refs(refs)) 
      end
    end

    # Match a single refspec against a list of refs.
    # For example:
    #  Refspec.new("refs/heads/*", "refs/remotes/origin/*", false).match_refs(["refs/heads/main", "refs/heads/feature"]) 
    #  => {"refs/remotes/origin/*"=>["refs/heads/*", false]}
    def match_refs(refs)
      # If source doesn't contain "*", it's a simple ref mapping.
      # If the source refspec doesn't contain a wildcard, it refers to a specific branch.
      # In this case, we directly map the target to the source and return.
      return { target => [source, forced]} if !source.to_s.include?("*")
      
      # If source contains "*", it's a wildcard refspec.
      # Construct a regular expression from the source refspec, 
      # replacing "*" with "(.*)" to capture the branch name.
      pattern = /^#{ source.sub("*", "(.*)") }$/ #  e.g., for "refs/heads/*", it becomes /^refs\/heads\/(.*)$/
      # Initialize an empty hash to store the mappings.
      mappings = {}

      # Iterate over each ref in the provided list of refs
      refs.each do |ref|
        # Try to match the current ref against the constructed pattern.
        next unless match = pattern.match(ref) # if pattern.match(ref) returns nil, skip to the next ref
        
        # If the match is successful, extract the captured branch name (if any).
        # match[1] contains the captured group from the regex, which is the branch name in this case.
        # If there is a captured branch name, substitute the "*" in the target refspec with the actual name.
        dst = match[1] ? target.sub("*", match[1]) : target # if match[1] is nil, use the target as is
        # Add the mapping to the `mappings` hash. 
        # The key is the calculated destination ref, and the value is an array containing the original ref and the forced flag.
        mappings[dst] = [ref, forced] # e.g., {"refs/remotes/origin/main"=>["refs/heads/main", false]}
      end

      # Return the hash containing the ref mappings.
      mappings # e.g., {"refs/remotes/origin/main"=>["refs/heads/main", false], "refs/remotes/origin/feature"=>["refs/heads/feature", false]}
    end


  end

end
