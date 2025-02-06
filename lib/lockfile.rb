# Implements file locking mechanism for safe concurrent access
# Similar to Git's index.lock mechanism to prevent concurrent modifications
class Lockfile
  # Custom error classes for specific failure scenarios
  MissingParent = Class.new(StandardError) # Parent directory doesn't exist
  NoPermission = Class.new(StandardError)  # No permission to create/write file
  StaleLock = Class.new(StandardError)     # Trying to use lock that isn't held
  LockDenied = Class.new(StandardError)    # Unable to acquire lock

  # Initialize a new lockfile
  # @param path [String, Pathname] Path to the file to be protected
  def initialize(path)
    @file_path = path            # Original file to be updated
    @lock_path = path.sub_ext('.lock')  # Lock file path (original + .lock)
    @lock = nil                  # File handle for the lock file
  end

  # Attempt to acquire the lock for updating the file
  # @return [Boolean] true if lock acquired
  # @raise [LockDenied] if lock already exists
  # @raise [MissingParent] if parent directory missing
  # @raise [NoPermission] if permission denied
  def hold_for_update
    unless @lock
      flags = File::RDWR | File::CREAT | File::EXCL  # Changed from RDWR to WRONLY
      @lock = File.open(@lock_path, flags)
    end
    true
  rescue Errno::EEXIST # File exists - another process has the lock
    raise LockDenied, "Unable to create '#{ @lock_path }': File exists." 
  rescue Errno::ENOENT => error  # Parent directory missing
    raise MissingParent, error.message
  rescue Errno::EACCES => error  # Permission denied
    raise NoPermission, error.message
  end 

  # Write data to the lock file
  # @param string [String] Data to write
  # @raise [StaleLock] if lock not held
  def write(string)
    raise_on_stale_lock  # Ensure we have the lock
    @lock.write(string) # Write to the lock file
  end

  # Commit changes by replacing original file with lock file
  # @raise [StaleLock] if lock not held
  def commit 
    raise_on_stale_lock

    @lock.close # Close the lock file
    File.rename(@lock_path, @file_path) # Atomically replace original with lock file
    @lock = nil # Clear the loc
  end

  # Abandon changes and remove lock file
  # @raise [StaleLock] if lock not held
  def rollback
    raise_on_stale_lock

    @lock.close
    File.unlink(@lock_path)
    @lock = nil
  end

  private

  # Verify lock is held before operations
  # @raise [StaleLock] if lock not held
  def raise_on_stale_lock
    unless @lock
      raise StaleLock, "Not holding lock on file: #{ @lock_path }"
    end
  end

end