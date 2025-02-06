require 'set'
require "sorted_set"
require "digest/sha1"

require_relative "./index/entry"
require_relative './lockfile'
require_relative './index/checksum'

# Manages the Git index (staging area)
# Handles reading, writing, and modification of the index file
# Similar to Git's index implementation
class Index 
  # Format string for index header
  # a4 = 4-byte signature
  # N2 = Two 32-bit unsigned integers (version and entry count)
  HEADER_FORMAT = 'a4N2'
  HEADER_SIZE = 12
  SIGNATURE = 'DIRC'    # "DirCache" signature for index files
  VERSION = 2           # Index format version

  # Minimum size of an index entry in bytes
  ENTRY_MIN_SIZE = 64

  # Initialize index with pathname and lockfile
  # @param pathname [Pathname] Path to index file
  def initialize(pathname)
    @pathname = pathname
    @lockfile = Lockfile.new(pathname)
    clear
  end

  # Add or update a file in the index
  # @param pathname [Pathname] File path
  # @param oid [String] Object ID of the blob
  # @param stat [File::Stat] File status information
  def add(pathname, oid, stat)
    entry = Entry.create(pathname, oid, stat)
    discard_conflicts(entry)
    store_entry(entry)
    @changed = true
  end

  # Remove any conflicting entries for a new entry
  # Removes parent directories and child entries
  # @param entry [Entry] New entry being added
  def discard_conflicts(entry)
    entry.parent_directories.each { |parent| remove_entry(parent) }
    remove_children(entry.path)
  end

  # Remove all child entries of a path
  # @param path [String] Parent path
  def remove_children(path)
    return if !@parents.has_key?(path)

    children = @parents[path].clone
    children.each { |child| remove_entry(child) }
  end

  # Remove an entry and update parent directories
  # @param pathname [Pathname] Path to remove
  def remove_entry(pathname)
    entry = @entries[pathname.to_s]
    return if !entry

    @keys.delete(entry.key)
    @entries.delete(entry.key)

    entry.parent_directories.each do |dirname|
      dir = dirname.to_s
      @parents[dir].delete(entry.path)
      @parents.delete(dir) if @parents[dir].empty?

    end
  end
  
  # Start write operation and initialize checksum
  def begin_write
    @digest = Digest::SHA1.new
  end

  # Write data while updating checksum
  # @param data [String] Data to write
  def write(data)
    @lockfile.write(data)
    @digest.update(data)
  end
  
  # Finish write operation and write checksum
  def finish_write
    @lockfile.write(@digest.digest)
    @lockfile.commit
  end

  # Iterate through index entries in sorted order
  # @yield [Entry] Each index entry
  def each_entry
    if block_given? 
      @keys.each {|key| yield @entries[key]}
    else 
      enum_for(:each_entry)
    end 
  end

  # Release the lock on the index file
  def release_lock
    @lockfile.rollback
  end

  # Lock index for updates and load contents
  def load_for_update
    @lockfile.hold_for_update
    load 
  end

  # Check if a path is tracked in the index
  # @param path [String, Pathname] Path to check
  # @return [Boolean] true if path is tracked
  def tracked?(path)
    @entries.has_key?(path.to_s) or @parents.has_key?(path.to_s)
  end

  # Update file statistics for an entry
  # @param entry [Entry] Entry to update
  # @param stat [File::Stat] New file statistics
  def update_entry_stat(entry, stat)
    entry.update_stat(stat)
    @changed = true
  end

  # Load index contents from disk
  def load 
    clear 
    file = open_index_file

    if file
      reader = Checksum.new(file)
      count = read_header(reader)
      read_entries(reader, count)
      reader.verify_checksum
    end 
  ensure 
    file&.close
  end

  # Reset index to empty state
  def clear 
    @entries = {}
    @keys = SortedSet.new
    # Parents property should create a data structure like this
    # @parents = {
    # "nested" => Set.new(["nested/bob.txt", "nested/inner/claire.txt"]),
    # "nested/inner" => Set.new(["nested/inner/claire.txt"])
    # }
    @parents = Hash.new { |hash, key| hash[key] = Set.new() }
    @changed = false
  end

   # Write index updates to disk
  # Writes header, entries and checksum
  def write_updates
    return @lockfile.rollback if @changed == false

    writer = Checksum.new(@lockfile)
    header = [SIGNATURE, VERSION, @entries.size].pack(HEADER_FORMAT)
    writer.write(header)
    each_entry { |entry| writer.write(entry.to_s) }

    writer.write_checksum

    @lockfile.commit
    @changed = false
  end

  def entry_for_path(path)
    @entries[path.to_s]
  end

  def tracked_file?(path)
    (0..3).any? { |stage| @entries.has_key?([path.to_s, stage]) }
  end

  # Deletes the entry at exactly the given pathname if one exists, and deletes 
  # any index entries that are nested under that name
  def remove(pathname)
    remove_entry(pathname)
    remove_children(pathname.to_s)
    @changed = true
  end

  private

  # Open index file for reading
  # @return [File, nil] File handle or nil if not found
  def open_index_file
    File.open(@pathname, File::Constants::RDONLY)
  rescue Errno::ENOENT
    nil
  end

  # Read and validate index header
  # @param reader [Checksum] Checksummed reader
  # @return [Integer] Number of entries
  def read_header(reader)
    data = reader.read(HEADER_SIZE)
    signature, version, count = data.unpack(HEADER_FORMAT)

    if signature != SIGNATURE
      raise Invalid, "Signature: expected #{SIGNATURE} but found #{signature}"
    end

    if version != VERSION
      raise Invalid, "Version: expected #{VERSION} but found #{version}"
    end

    count
  end

  # Read all index entries
  # @param reader [Checksum] Checksummed reader
  # @param count [Integer] Number of entries to read
  def read_entries(reader, count)
    count.times do 
      entry = reader.read(ENTRY_MIN_SIZE)

      until entry.byteslice(-1) == "\0"
        entry.concat(reader.read(ENTRY_BLOCK))
      end

      store_entry(Entry.parse(entry))
    end
  end

  # Store an entry in the index
  # Updates entries, keys and parent directories
  # @param entry [Entry] Entry to store
  def store_entry(entry)
    @keys.add(entry.key)
    @entries[entry.key] = entry

    entry.parent_directories.each do |dirname|
      @parents[dirname.to_s].add(entry.path)
    end
  end

 
end
