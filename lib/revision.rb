# The Revision class handles parsing and validation of Git-like revision expressions
# such as HEAD, master, HEAD^, master~2 etc.
class Revision
  InvalidObject = Class.new(StandardError)

  COMMIT = "commit"

  HintedError = Struct.new(:message, :hint)
  # Data structures to represent different types of revision expressions
  Ref = Struct.new(:name) do  # Simple reference like 'master' or 'HEAD' 
    def resolve(context)
      context.read_ref(name) # try and convert a refname like HEAD or master into a commit ID
    end
  end

  Parent = Struct.new(:rev, :n) do  # Parent reference like 'master^'
    def resolve(context)
      # As parent nodes contain another revision node inside themselves, we call resolve on its inner node, and 
      # pass the result of that to another method commit_parent, which will load the given object ID to get a commit 
      # and then return the commit`s parent ID
      context.commit_parent(rev.resolve(context), n)
    end
  end

  Ancestor = Struct.new(:rev, :n) do # Ancestor reference like 'master~2'
    def resolve(context)
      oid = rev.resolve(context)
      n.times { oid = context.commit_parent(oid)}
      oid
    end
  end

  # Regular expression defining invalid characters and patterns in reference names
  # Follows Git's reference naming rules
  INVALID_NAME = /
  ^\.           # Cannot start with a dot
  | \/\.        # Cannot contain slash followed by dot
  | \.\.        # Cannot contain two consecutive dots
  | ^\/         # Cannot start with slash
  | \/$         # Cannot end with slash
  | \.lock$     # Cannot end with .lock
  | @\{         # cannot contain @{
  | [\x00-\x20*:?\[\\^~\x7f] # Cannot contain special characters
  /x

  HEAD = "HEAD"
  
  # Pattern matching for parent reference (ends with zero or more digits)
  PARENT = /^(.+)\^(\d*)$/

  # Pattern matching for ancestor reference (ends with ~N where N is a number)
  ANCESTOR = /^(.+)~(\d+)$/
  
  # Common reference aliases
  REF_ALIASES = {
    "@" => "HEAD"  # @ is an alias for HEAD
  }

  # Parses a revision string and returns a structured representation
  # These structures are called abstract syntax trees or ASTs
  # Returns nil if the revision string is invalid
  # @param revision [String] the revision expression to parse
  # @return [Ref, Parent, Ancestor, nil] the parsed revision structure
  def self.parse(revision)
    if match = PARENT.match(revision)
      rev = Revision.parse(match[1])
      rev ? Parent.new(rev) : nil
    elsif match = ANCESTOR.match(revision)
      rev = Revision.parse(match[1])
      rev ? Ancestor.new(rev, match[2].to_i) : nil
    elsif Revision.valid_ref?(revision)
      name = REF_ALIASES[revision] || revision
      Ref.new(name)
    end
  end

  attr_reader :errors

  def initialize(repo, expression)
    @repo = repo
    @expr = expression
    @query = Revision.parse(@expr)
    @errors = []
  end

  def resolve(type = nil)
    oid = @query&.resolve(self)
    # Check that the ID that results from evaluating the 
    oid = nil if type and not load_typed_object(oid, type)

    return oid if oid

    raise InvalidObject, "Not a valid object name: '#{ @expr }'"
  end

  # Validates if a reference name follows Git naming rules
  # @param revision [String] the reference name to validate
  # @return [Boolean] true if valid, false otherwise
  def self.valid_ref?(revision)
    INVALID_NAME =~ revision ? false : true
  end

  # Retrieves the nth parent commit of a given commit object
  # @param oid [String] The object ID (SHA-1) of the commit whose parent we want to find
  # @param n [Integer] Which parent to retrieve (defaults to 1, matters for merge commits with multiple parents)
  # @return [String, nil] The OID of the nth parent, or nil if the commit or parent doesn't exist.
  def commit_parent(oid, n = 1)
    return nil if !oid

    commit = load_typed_object(oid, COMMIT)
    return nil if !commit
    
    # Return the OID of the nth parent of the commit.
    commit.parents[n - 1]
  end

  def load_typed_object(oid, type)
    return nil if !oid

    object = @repo.database.load(oid)

    if object.type == type
      object
    else 
      message = "object #{ oid } is a #{ object.type }, not a #{ type }"
      @errors.push(HintedError.new(message, []))

      nil
    end
  end

  # Delegates to the Red,s object attached to the repository
  def read_ref(name)
    oid = @repo.refs.read_ref(name)

    return oid if oid

    candidates = @repo.database.prefix_match(name)
    return candidates.first if candidates.size == 1

    if candidates.size > 1
      log_ambiguos_sha1(name, candidates)
    end

    nil
  end

  # Constructs the error message by reading all the candidate IDs from the database and listing 
  # out their short Id and type.
  def log_ambiguos_sha1(name, candidates)
    objects = candidates.sort.map do |oid|
      object = @repo.database.load(oid)
      short = @repo.database.short_oid(object.oid)
      info = "  #{ short } #{ object.type }"

      if object.type == "commit"
        "#{ info } #{ object.author.short_date } - #{ object.title_line }"
      else 
        info
      end
    end

    message = "short SHA1 #{ name } is ambiguos"
    hint = ["The candidates are:"] + objects
    @errors.push(HintedError.new(message, hint))
  end

end

# puts Revision.parse "@^"  #<struct Revision::Parent rev=#<struct Revision::Ref name="HEAD">>
# puts Revision.parse "HEAD~42" #<struct Revision::Ancestor rev=#<struct Revision::Ref name="HEAD">, n=42>
# puts Revision.parse "master^^" #<struct Revision::Parent rev=#<struct Revision::Parent rev=#<struct Revision::Ref name="master">>>
# puts Revision.parse "master~2" #<struct Revision::Ancestor rev=#<struct Revision::Ref name="master">, n=2>