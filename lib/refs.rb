# Manages Git references (refs) including HEAD
# Handles reading and updating reference pointers
class Refs 
  InvalidBranch = Class.new(StandardError)
  INVALID_NAME = /
  ^\.
  | \/\.
  | \.\.
  | ^\/
  | \/$
  | \.lock$
  | @\{
  | [\x00-\x20*:?\[\\^~\x7f]
  /x

  HEAD = "HEAD"

  # Initialize refs manager
  # @param pathname [Pathname] Path to .git directory
  def initialize(pathname)
    @pathname = pathname
    @refs_path = @pathname.join("refs")
    @heads_path = @refs_path.join("heads")
  end

  # Update HEAD reference with new commit OID
  # Uses lockfile to ensure atomic updates
  # @param oid [String] Object ID of new commit
  # @return [void]
  def update_head(oid)
    update_ref_file(@pathname.join(HEAD), oid)
  end

  # Get path to HEAD reference file
  # @return [Pathname] Path to HEAD file
  def head_path
    @pathname.join('HEAD')
  end

  # Read current HEAD reference
  # @return [String, nil] Current HEAD commit OID or nil if not set
  def read_head
    if File.exist?(head_path)
      File.read(head_path).strip
    end
  end

  def create_branch(branch_name, start_oid)
    path = @heads_path.join(branch_name)

    if INVALID_NAME =~ branch_name
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
    lockfile.write(oid)
    lockfile.write("\n")
    lockfile.commit

  rescue Lockfile::MissingParent
    FileUtils.mkdir_p(path.dirname)
    retry
  end

  def read_ref(name)
    path = path_for_name(name)
    path ? read_ref_file(path) : nil
  end

  def path_for_name(name)
    prefixes = [@pathname, @refs_path, @heads_path]
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

end