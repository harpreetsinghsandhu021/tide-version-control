require "pathname"
require_relative "../repository"

module Command 
  # Implements the 'tide add' command to stage files for commit
  # Similar to 'git add', this command adds file contents to the index
  class Add < Base

    # Error message displayed when the index file is locked by another process
    LOCKED_INDEX_MESSAGE = <<~MSG
     Another tide process seems to be running in this repository. 
     Please make sure all processes are terminated then try again. 
     If it still fails, a tide process may have crashed in this
     repository earlier: remove the file manually to continue.
    MSG

    # Main execution method for the add command
    # Loads the index, adds specified files, and writes updates
    # @return [void]
    def run
      repo.index.load_for_update
      expanded_paths.each { |path| add_to_index(path)}
      repo.index.write_updates
      exit 0
    rescue Lockfile::LockDenied => error
      handle_locked_index(error)
    rescue Workspace::MissingFile => error
      handle_missing_file(error)
    rescue Workspace::NoPermission => error
      handle_permission_error(error)
    end

    private 

    # Expands file paths and resolves globs
    # @return [Array<Pathname>] List of expanded file paths
    def expanded_paths
      @args.flat_map do |path|
        repo.workspace.list_files(expanded_pathname(path))
      end
    end

    # Adds a single file to the index
    # Creates a blob object and updates the index entry
    # @param path [Pathname] Path to the file to add
    # @return [void]
    def add_to_index(path)
      data = repo.workspace.read_file(path)
      stat = repo.workspace.stat_file(path)

      blob = Database::Blob.new(data)
      repo.database.store(blob)
      repo.index.add(path, blob.oid, stat)
    end

    # Handles error when index file is locked
    # @param error [Lockfile::LockDenied] Lock error
    # @return [void]
    def handle_locked_index(error)
      @stderr.puts "fatal: #{ error.message }"
      @stderr.puts 
      @stderr.puts LOCKED_INDEX_MESSAGE
      exit 128
    end

    # Handles error when file is missing
    # @param error [Workspace::MissingFile] Missing file error
    # @return [void]
    def handle_missing_file(error)
      @stderr.puts "fatal: #{ error.message }"
      repo.index.release_lock
      exit 128
    end

    # Handles error when file permissions deny access
    # @param error [Workspace::NoPermission] Permission error
    # @return [void]
    def handle_permission_error(error)
      @stderr.puts "error: #{ error.message }"
      @stderr.puts "fatal: adding files failed"
      repo.index.release_lock
      exit 128
    end

  end
end