require "digest/sha1"
require "zlib"
require "strscan"
require "forwardable"

require_relative "./database/blob"
require_relative "./database/tree"
require_relative "./database/commit"
require_relative "./database/tree_diff"
require_relative "./database/loose"
require_relative "./database/backends"
require_relative "./temp_file"

# Database class handles storage and retrieval of git objects
# It manages the object database in the .git/objects directory
class Database

  TYPES = {
    "blob" => Blob, 
    "tree" => Tree,
    "commit" => Commit
  }

  Raw = Struct.new(:type, :size, :data)

  extend Forwardable

  def_delegators :@backend, :has?, :load_info, :load_raw, :prefix_match, :pack_path, :reload

  # @param pathname [Pathname] Path to the .git/objects directory
  # @param objects [Hash] Caching the result of reading an object from disk
  def initialize(pathname)
    @objects = {}
    @backend = Backends.new(pathname)
  end

  # Stores a tide object (blob, tree, or commit) in the database
  # @param object [Object] The object to store
  # @return [void]
  def store(object)
    content = serialize_object(object)
    object.oid = hash_content(content)
    @backend.write_object(object.oid, content)
  end

  # Generates a hash for an object without storing it
  # @param object [Object] The object to hash
  # @return [String] SHA1 hash of the object
  def hash_object(object)
    hash_content(serialize_object(object))
  end

  def load(oid)
    @objects[oid] ||= read_object(oid)
  end

  def short_oid(oid)
    oid[0..6]
  end

   # Calculating and returning the diff between two commits or trees
  def tree_diff(a, b, filter = PathFilter.new)
    diff = TreeDiff.new(self)
    diff.compare_oids(a, b, filter)
    diff.changes
  end


  def load_tree_entry(oid, pathname)
    commit = load(oid)

    # From this commit, we get its 'tree', which is like a directory listing of all the files at that point in time. 
    # We create an 'Entry' representing this top-level directory. It's like opening the main folder of your project.
    root = Entry.new(commit.tree, Tree::TREE_MODE)

    # If no specific 'pathname' is provided, we just return the 'root' directory entry. 
    # It's like saying "just show me what's in the main folder, I don't need to go deeper."
    return root if !pathname

    #  If a 'pathname' is provided, this means we want to find a specific file or folder within the commit's tree.

    # We split the 'pathname' into individual parts (like splitting a file path into its folders).
    pathname.each_filename.reduce(root) do |entry, name|
      entry ? load(entry.oid).entries[name] : nil
    end
  end

  # Creates a flattened list of all files and directories stored within a given tree object in the database.
  def load_tree_list(oid, pathname = nil)
    return {} if !oid

    entry = load_tree_entry(oid, pathname) # Get the entry object for the root. 
    list = {}

    # Recursively build the list starting from the given entry and prefix.
    build_list(list, entry, pathname || Pathname.new(""))
    list
  end

  def build_list(list, entry, prefix)
    return if !entry

    # Base case: If entry is a blob(file), add it to the list and return.
    return list[prefix.to_s] = entry if !entry.tree?

    # If entry is a tree(directory), iterate through its entries.
    load(entry.oid).entries.each do |name, item| 
      # Recursively call build_list with updated prefix.
      build_list(list, item, prefix.join(name))
    end
  end

  def tree_entry(oid)
    Entry.new(oid, Tree::TREE_MODE)
  end

 

 

  def pack_path
    @pathname.join("pack")
  end


  private

  # Converts an object into its git-compatible string representation
  # Format: "type size\0content"
  # @param object [Object] Object to serialize
  # @return [String] Serialized object content
  def serialize_object(object)
    string = object.to_s.force_encoding(Encoding::ASCII_8BIT)
    "#{ object.type } #{ string.bytesize }\0#{ string }"
  end

  # Creates SHA1 hash of content
  # @param content [String] Content to hash
  # @return [String] 40-character hexadecimal SHA1 hash
  def hash_content(content)
    Digest::SHA1.hexdigest(content)
  end

  def read_object(oid)
   raw = load_raw(oid)
   scanner = StringScanner.new(raw.data)

   object = TYPES[raw.type].parse(scanner)
   object.oid = oid

   object
  end
end