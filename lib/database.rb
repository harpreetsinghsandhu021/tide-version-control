require "digest/sha1"
require "zlib"
require "strscan"
require_relative "./database/blob"
require_relative "./database/tree"
require_relative "./database/commit"
require_relative "./database/tree_diff"

# Database class handles storage and retrieval of git objects
# It manages the object database in the .git/objects directory
class Database

  TYPES = {
    "blob" => Blob, 
    "tree" => Tree,
    "commit" => Commit
  }

  # Characters used for generating temporary filenames
  TEMP_CHARS = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a

  # @param pathname [Pathname] Path to the .git/objects directory
  # @param objects [Hash] Caching the result of reading an object from disk
  def initialize(pathname)
    @pathname = pathname
    @objects = {}
  end

  # Stores a tide object (blob, tree, or commit) in the database
  # @param object [Object] The object to store
  # @return [void]
  def store(object)
    content = serialize_object(object)
    object.oid = hash_content(content)
    write_object(object.oid, content)
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

  def object_path(oid)
    @pathname.join(oid[0..1].to_s, oid[2..-1].to_s)
  end

  def short_oid(oid)
    oid[0..6]
  end

 

  def prefix_match(name)
    dirname = object_path(name).dirname
    oids = Dir.entries(dirname).map do |filename|
      "#{ dirname.basename }#{ filename }"
    end
    oids.select { |oid| oid.start_with?(name) }
  rescue Errno::ENOENT
    []
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

  # Writes an object to the database using git's content-addressable storage scheme
  # Objects are stored in subdirectories based on first 2 characters of their hash
  # @param oid [String] Object ID (SHA1 hash)
  # @param content [String] Object content to write
  def write_object(oid, content)
    # Split the oid into directory prefix (first 2 chars) and filename (remaining chars)
    object_path = object_path(oid)
    return if File.exist?(object_path)
    
    dirname = object_path.dirname 
    temp_path = dirname.join(generate_temp_name)

    begin 
      flags = File::RDWR | File::CREAT | File::EXCL
      file = File.open(temp_path, flags)
    rescue Errno::ENOENT
      # Create directory if it doesn't exist and retry
      Dir.mkdir(dirname)
      file = File.open(temp_path, flags)
    end 

    # Compress content using zlib deflate algorithm
    compressed = Zlib::Deflate.deflate(content, Zlib::BEST_SPEED)

    file.write(compressed)
    file.close

    # Atomic rename of temp file to final location
    File.rename(temp_path, object_path)
  end
  
  # Generates a random temporary filename
  # @return [String] Random filename in format "tmp_obj_XXXXXX"
  def generate_temp_name
    "tmp_obj_#{(1..6).map {TEMP_CHARS.sample}.join("") }"
  end


  def read_object(oid)
    # Reads the object from disk and then decompress it using zlib
    data = Zlib::Inflate.inflate(File.read(object_path(oid)))
    # creates a StringScanner instance which can be used for parsing data
    scanner = StringScanner.new(data)

    # use stringscanner to scan_until we find a space, giving us the object`s type
    type = scanner.scan_until(/ /).strip
    # scan_until we find a null byte, giving us the size
    _size = scanner.scan_until(/\0/)[0..-2]

    object = TYPES[type].parse(scanner) # process the rest of the data
    object.oid = oid # attach the given object ID to the object

    object
  end

 

end