require "fileutils"
require "pathname"
require_relative "./lockfile"
require_relative "./revision"

# Manages Git references (refs) including HEAD
# Handles reading and updating reference pointers
class Refs 
  InvalidBranch = Class.new(StandardError)

  HEAD = "HEAD"
  ORIG_HEAD = "ORIG_HEAD" # Stores the original HEAD when resetting the workspace in case 
  # user wants to move to this head again. 
  
  StaleValue = Class.new(StandardError)
  
  REFS_DIR = Pathname.new("refs")
  HEADS_DIR = REFS_DIR.join("heads")
  REMOTES_DIR = REFS_DIR.join("remotes")

  SymRef = Struct.new(:refs, :path) do 
    def read_oid
      refs.read_ref(path)
    end

    def head?
      path == HEAD
    end

    def short_name
      refs.short_name(path)
    end

    def branch?
      path.start_with?("refs/heads/")
    end

    def remote?
      path.start_with?("refs/remotes/")
    end

  end
  Ref = Struct.new(:oid) do 
    def read_oid 
      oid
    end
  end

  SYMREF = /^ref: (.+)$/

  # Initialize refs manager
  # @param pathname [Pathname] Path to .git directory
  def initialize(pathname)
    @pathname = pathname
    @refs_path = @pathname.join(REFS_DIR)
    @heads_path = @pathname.join(HEADS_DIR)
    @remotes_path = @pathname.join(REMOTES_DIR)
  end

  # Update HEAD reference with new commit OID
  # Uses lockfile to ensure atomic updates
  # @param oid [String] Object ID of new commit
  # @return [void]
  def update_head(oid)
    # update_ref_file(@pathname.join(HEAD), oid)
    update_symref(@pathname.join(HEAD), oid)
  end

  # Get path to HEAD reference file
  # @return [Pathname] Path to HEAD file
  def head_path
    @pathname.join('HEAD')
  end

  # Read current HEAD reference
  # @return [String, nil] Current HEAD commit OID or nil if not set
  def read_head
    read_symref(@pathname.join(HEAD))
  end

  def create_branch(branch_name, start_oid)
    path = @heads_path.join(branch_name)

    if !Revision.valid_ref?(branch_name)
      raise InvalidBranch, "'#{ branch_name }' is not a valid branch name."
    end

    if File.file?(path)
      raise InvalidBranch, "A branch named '#{ branch_name }' already exists."
    end

    update_ref_file(path, start_oid)

  end

  def update_ref_file(path, oid)
    lockfile = Lockfile.new(path)

    lockfile.hold_for_update 

    yield if block_given?

    if oid 
      write_lockfile(lockfile, oid)
    else
      File.unlink(path) rescue Errno::ENOENT
      lockfile.rollback
    end

  rescue Lockfile::MissingParent
    FileUtils.mkdir_p(path.dirname)
    retry
  rescue => error
    lockfile.rollback
    raise error
  end

  def write_lockfile(lockfile, oid)
    lockfile.write(oid)
    lockfile.write("\n")
    lockfile.commit
  end

  
  def update_symref(path, oid)
    lockfile = Lockfile.new(path)
    lockfile.hold_for_update
  
    ref = read_oid_or_symref(path)
  
    unless ref.is_a?(SymRef)
      write_lockfile(lockfile, oid)
      return ref&.oid
    end
  
    begin
      update_symref(@pathname.join(ref.path), oid)
    ensure
      lockfile.rollback
    end
  end

  def read_ref(name)
    path = path_for_name(name)
    path ? read_symref(path) : nil
  end

  def path_for_name(name)
    prefixes = [@pathname, @refs_path, @heads_path, @remotes_path]
    prefix = prefixes.find { |path| File.file? path.join(name) }

    prefix ? prefix.join(name) : nil
  end

  def read_ref_file(path)
    File.read(path).strip
  rescue Errno::ENONET
    nil
  end

  def set_head(revision, oid)
    head = @pathname.join(HEAD)
    path = @heads_path.join(revision)

    if File.file?(path)
      relative = path.relative_path_from(@pathname)
      update_ref_file(head, "ref: #{ relative }")
    else
      update_ref_file(head, oid)
    end
  end
  
  def read_oid_or_symref(path)
    data = File.read(path).strip
    match = SYMREF.match(data)

    match ? SymRef.new(self, match[1]) : Ref.new(data)
  rescue Errno::ENOENT
    nil
  end

  def read_symref(path)
    ref = read_oid_or_symref(path)

    case ref
    when SymRef then read_symref(@pathname.join(ref.path))
    when Ref then ref.oid
    end
  end

  def current_ref(source = HEAD)
    ref = read_oid_or_symref(@pathname.join(source))

    case ref 
    when SymRef then current_ref(ref.path)
    when Ref, nil then SymRef.new(self, source)
    end
  end

  def list_branches
    list_refs(@heads_path)
  end

  def list_remotes
    list_refs(@remotes_path)
  end

  def list_refs(dirname)
    names = Dir.entries(dirname) - [".", ".."]

    names.map { |name| dirname.join(name) }.flat_map do |path|
      if File.directory?(path)
        list_refs(path)
      else 
        path = path.relative_path_from(@pathname)
        SymRef.new(self, path.to_s)
      end
    end

  rescue Errno::ENOENT
    []
  end

  # Takes a full reference path (like "refs/heads/main") and returns a shortened,
  #  more readable version (like "main").
  def short_name(path)
    path = @pathname.join(path)

    prefix = [@remotes_path, @heads_path, @pathname].find do |dir|
      path.dirname.ascend.any? { |parent| parent == dir }
    end

    path = path.relative_path_from(prefix) if prefix
    path.to_s
  end

  def delete_branch(branch_name)
    path = @heads_path.join(branch_name)

    lockfile = Lockfile.new(path)
    lockfile.hold_for_update

    oid = read_symref(path)
    raise InvalidBranch, "branch '#{ branch_name }' not found." if !oid

    File.unlink(path)
    delete_parent_directories(path)

    oid
  ensure
    lockfile.rollback
  end

  def delete_parent_directories(path)
    path.dirname.ascend do |dir|
      break if dir == @heads_path

      begin
        Dir.rmdir(dir)
      rescue Errno::ENOTEMPTY
        break
      end
    end
  end

  def reverse_refs
    table = Hash.new { |hash, key| hash[key] = [] }

    list_all_refs.each do |ref|
      oid = ref.read_oid
      table[oid].push(ref) if oid
    end

    table
  end

  def list_all_refs
    [SymRef.new(self, HEAD)] + list_refs(@refs_path)
  end

  def update_ref(name, oid)
    update_ref_file(@pathname.join(name), oid)
  end

  # Atomically updates a reference only if it hasn't changed
  # @param name [String] Name of the reference to update
  # @param old_oid [String, nil] Expected current commit ID
  # @param new_oid [String, nil] New commit ID to set
  # @raise [StaleValue] If reference value changed since last read
  def compare_and_swap(name, old_oid, new_oid)
    # Convert reference name to filesystem path
    path = @pathname.join(name)

    update_ref_file(path, new_oid) do 
      # Atomic update: Only proceed if nobody else modified the ref
      # Compare current value with what we expect it to be
      unless old_oid == read_symref(path)
        # Someone changed the ref while we weren't looking - abort
        raise StaleValue, "value of #{ name } changes since last read"
      end
    end
  end

  def long_name(ref)
    path = path_for_name(ref)
    return path.relative_path_from(@pathname).to_s if path

    raise InvalidBranch, 
    "the requested upstream branch '#{ ref }' does not exist"
  end

end
