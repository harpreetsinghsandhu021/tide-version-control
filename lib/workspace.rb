# Manages working directory operations
# Handles file listing, reading, and stat operations
class Workspace 
  # Files and directories to ignore when scanning
  IGNORE = ['.', '..', '.git', ".ruby-lsp"]

  # Custom errors for file operations
  MissingFile = Class.new(StandardError)    # Raised when file doesn't exist
  NoPermission = Class.new(StandardError)   # Raised when permission denied

  # Initialize workspace manager
  # @param pathname [Pathname] Root path of working directory
  def initialize(pathname)
    @pathname = pathname
  end

  # List all files recursively, excluding ignored ones
  # @param path [Pathname] Starting path for file listing
  # @return [Array<Pathname>] List of files relative to workspace root
  # @raise [MissingFile] if path doesn't exist
  def list_files(path = @pathname)
    relative = path.relative_path_from(@pathname)

    if File.directory?(path)
        filenames = Dir.entries(path) - IGNORE
        filenames.flat_map { |name| list_files(path.join(name)) }
    elsif File.exist?(path)
        [relative]
    else 
        raise MissingFile, "pathspec '#{ relative }' did not match any files"
    end
  end

  # List contents of a directory with their stats
  # @param dirname [String, nil] Directory to list, nil for root
  # @return [Hash] Map of relative paths to File::Stat objects
  def list_dir(dirname)
    path = @pathname.join(dirname || "")
    entries = Dir.entries(path) - IGNORE
    stats = {}

    entries.each do |name|
      relative = path.join(name).relative_path_from(@pathname)
      stats[relative.to_s] = File.stat(path.join(name))
    end
    stats
  end

  # Read contents of a file
  # @param path [String, Pathname] Path to file relative to workspace root
  # @return [String] File contents
  # @raise [NoPermission] if file can't be read
  def read_file(path)
    File.read(@pathname.join(path))
  rescue Errno::EACCES
    raise NoPermission, "open('#{ path }'): Permission denied"
  end

  # Get file status information
  # @param path [String, Pathname] Path to file relative to workspace root
  # @return [File::Stat] File status information
  # @raise [NoPermission] if file can't be accessed
  def stat_file(path)
    File.stat(@pathname.join(path))
  rescue Errno::ENOENT, Errno::ENOTDIR
    nil
  rescue Errno::EACCES
    raise NoPermission, "stat('#{ path }'): Permission denied"
  end

  # Takes a Migration and executes its change plan
  def apply_migration(migration)
    apply_change_list(migration, :delete)

    migration.rmdirs.sort.reverse_each { |dir| remove_directory(dir)}
    migration.mkdirs.sort.each { |dir| make_directory(dir)}
    apply_change_list(migration, :update)
    apply_change_list(migration, :create)
  end

  # Puts the files in the workspace in the correct state
  def apply_change_list(migration, action)
    migration.changes[action].each do |filename, entry|
      path = @pathname.join(filename)

      FileUtils.rm_rf(path)
      next if action == :delete

      flags = File::Constants::WRONLY | File::Constants::CREAT | File::Constants::EXCL
      data = migration.blob_data(entry.oid)

      File.open(path, flags) { |file| file.write(data) }
      File.chmod(entry.mode, path)
    end
  end

  def remove_directory(dirname)
    Dir.rmdir(@pathname.join(dirname))
  rescue Errno::ENONET, Errno:: ENOTDIR, Errno::ENOTEMPTY
  end

  def make_directory(dirname)
    path = @pathname.join(dirname)
    stat = stat_file(path)

    File.unlink(path) if stat&.file?
    Dir.mkdir(path) if !stat&.directory?
  end

end

