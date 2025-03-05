require_relative "./remotes/refspec"
require_relative "./remotes/remote"
require_relative "./refs"

# Manages remote repository configurations and operations
# This class handles the creation, deletion, and querying of git remotes
# Similar to git's remote repository management system
class Remotes 
  # Default remote name used when no specific remote is specified
  DEFAULT_REMOTE = "origin"
  # Custom error class for handling remote-related exceptions
  InvalidBranch = Class.new(StandardError)
  InvalidRemote = Class.new(StandardError)

  # Initializes a new Remotes manager
  # @param config [Config] Configuration object for storing remote settings
  def initialize(config)
    @config = config
  end

  # Adds a new remote repository to the configuration
  # @param name [String] Name of the remote (e.g., 'origin')
  # @param url [String] URL of the remote repository
  # @param branches [Array<String>] List of branches to track (defaults to ['*'])
  # @raise [InvalidRemote] if remote already exists
  # Note: If no branches specified, tracks all branches (*)
  def add(name, url, branches = [])
    branches = ["*"] if branches.empty?
    @config.open_for_update

    if @config.get(["remote", name, url])
      @config.save
      raise InvalidRemote, "remote #{ name } already exists."
    end

    # Configure the remote's URL
    @config.set(["remote", name, "url"], url)

    # Set up tracking for specified branches
    # Creates refspec mappings for each tracked branch
    branches.each do |branch|
      source = Refs::HEADS_DIR.join(branch)
      target = Refs::REMOTES_DIR.join(name, branch)
      refspec = Refspec.new(source, target, true)

      @config.add(["remote", name, "fetch"], refspec.to_s)
    end

    @config.save
  end

  # Removes a remote repository from the configuration
  # @param name [String] Name of the remote to remove
  # @raise [InvalidRemote] if remote doesn't exist
  # Note: This operation is destructive and cannot be undone
  def remove(name)
    @config.open_for_update

    if !@config.remove_section(["remote", name])
      raise InvalidRemote, "No such remote: #{ name }"
    end
  ensure
    # Ensures config is saved even if an error occurs
    @config.save
  end

  # Lists all configured remote repositories
  # @return [Array<String>] Names of all configured remotes
  # Note: Opens config in read-only mode
  def list_remotes
    @config.open
    @config.subsections("remote")
  end

  # Retrieves configuration for a specific remote
  # @param name [String] Name of the remote
  # @return [Remote, nil] Remote object if found, nil otherwise
  # Note: Returns nil instead of raising an error if remote doesn't exist
  def get(name)
    @config.open
    return nil if !@config.section?(["remote", name])

    Remote.new(@config, name)
  end

  def set_upstream(branch, upstream)
    list_remotes.each do |name|
      ref = get(name).set_upstream(branch, upstream)
      return [name, ref] if ref
    end

    raise InvalidBranch, 
    "Cannot setup tracking information; " + "starting point '#{ upstream }' is not a branch"
  end
  
  def unset_upstream(branch)
    @config.open_for_update
    @config.unset(["branch", branch, "remote"])
    @config.unset(["branch", branch, "merge"])
    @config.save
  end

  def get_upstream(branch)
    @config.open
    name = @config.get(["branch", branch, "remote"])
    get(name)&.get_upstream(branch)
  end

end