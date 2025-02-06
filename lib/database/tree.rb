require_relative "entry"

class Database
  # Represents a tree object in the version control system
  # Similar to Git's tree object, represents directories and their contents
  class Tree
    # Format string for packing tree entries
    # Z* = null-terminated string for name
    # H40 = 40 hex digits for SHA1
    ENTRY_FORMAT = 'Z*H40'

    # File mode for regular files (644 in octal)
    MODE = '100644'

    # File mode for directories (040000 in octal)
    TREE_MODE = 040000
    
    # Object ID (SHA1 hash) of the tree
    attr_accessor :oid

    # entries of the tree
    attr_reader :entries
  
    # Initialize an empty tree
    def initialize(entries = {})
      @entries = entries
    end
  
    # Returns the object type identifier
    # @return [String] Always returns "tree"
    def type
      "tree"
    end
  
    # Formats the tree entries in Git's tree object format
    # @return [String] Binary string containing packed tree entries
    def to_s
      entries = @entries.map do |name, entry|
        mode = entry.mode.to_s(8) # convert into an octal representation
        ["#{ mode } #{ name }", entry.oid].pack(ENTRY_FORMAT)
      end
  
      entries.join("")
    end
  
    # Builds a tree structure from a list of index entries
    # @param entries [Array<Entry>] List of index entries
    # @return [Tree] Root tree object containing all entries
    def self.build(entries)  
      root = Tree.new
      entries.each do |entry|
        root.add_entry(entry.parent_directories, entry)
      end
      root
    end
  
    # Recursively adds an entry to the tree structure
    # @param parents [Array<Pathname>] List of parent directories
    # @param entry [Entry] Index entry to add
    # @return [void]
    def add_entry(parents, entry)
      if parents.empty? 
        @entries[entry.basename] = entry
      else
        tree = @entries[parents.first.basename] ||= Tree.new
        tree.add_entry(parents.drop(1), entry)
      end
    end
  
    # Traverses the tree structure depth-first
    # @yield [Tree] Calls the block for each tree object
    # @return [void]
    def traverse(&block)
      @entries.each do |name, entry|
        entry.traverse(&block) if entry.is_a?(Tree)
      end
      block.call(self)
    end
  
    # Returns the mode for this tree
    # @return [Integer] Always returns TREE_MODE (040000)
    def mode 
      TREE_MODE
    end

    # Parse a tree
    def self.parse(scanner)
      entries = {}

      until scanner.eos?
        mode = scanner.scan_until(/ /).strip.to_i(8) # scan until next space and interpret integer as base 8
        name = scanner.scan_until(/\0/)[0..-2] # scan until the next byte to get the file`s name

        # read the next 20 bytes ,which are object ID, and unpack itusing the pattern H40
        # , which means a 40-digit hexadecimal string
        oid = scanner.peek(20).unpack("H40").first 
        scanner.pos += 20

        entries[name]  = Entry.new(oid, mode)
      end

      Tree.new(entries)
    end

  end
end