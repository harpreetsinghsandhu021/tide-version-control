class Database
  # Represents a commit object in the version control system
  # Similar to Git's commit object, stores tree reference, parent commit(s),
  # author information, and commit message
  class Commit
    # Object ID (SHA1 hash) of the commit
    # Set after the commit is stored in the database
    attr_accessor :oid
    attr_reader :tree, :parents, :message, :author
  
    # Initialize a new commit
    # @param parent [String, nil] OID of parent commit, nil for root commit
    # @param tree [String] OID of the tree object representing project state
    # @param author [Author] Author information including name, email, timestamp
    # @param message [String] Commit message
    def initialize(parents, tree, author, message)
      @parents = parents
      @tree = tree
      @author = author 
      @message = message
    end
  
    # Returns the object type identifier
    # @return [String] Always returns "commit"
    def type
      "commit"
    end
  
    # Formats the commit data in Git's commit object format
    # @return [String] Formatted commit content
    def to_s 
      lines = []
      lines.push("tree #{ @tree }")
      lines.concat(@parents.map { |oid| "parent #{ oid }"})
      lines.push("author #{ @author }")
      lines.push("committer #{ @author }")
      lines.push("")
      lines.push(@message)
  
      lines.join("\n")
    end

    # Parse a commit
    def self.parse(scanner)
      # a commit is stored as a series of line-delimited header fields, followed 
      # by a blank line, followed by a message
      headers = Hash.new { |hash, key| hash[key] = [] } 

      loop do 
        line = scanner.scan_until(/\n/).strip # read up to the next line break
        break if line == ""

        key, value = line.split(/ +/, 2) # split the line on first space
        headers[key].push(value)
      end


      Commit.new(headers["parent"], headers["tree"].first, Author.parse(headers["author"].first), scanner.rest)

    end

    def title_line
      @message.lines.first
    end

    def date 
      @author.time
    end

    def parent 
      @parents.first
    end

    # Check If it`s a merge by checking the parents becuase a merge will have two parents
    def merge?
      @parents.size > 1
    end

  end
end