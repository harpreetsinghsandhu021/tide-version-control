module Command
  # Remote command handler for managing git remote operations
  # This class provides functionality to add, remove, and list remote repositories
  # Similar to 'git remote' command in traditional git
  class Remote < Base
    
    # Configures command-line options for the remote command
    # @options[:verbose] - When true, displays detailed remote information
    # @options[:tracked] - Array of branch names to track from the remote
    def define_options
      @parser.on("-v", "--verbose") { @options[:verbose] = true }
      @options[:tracked] = []
      @parser.on("-t <branch>") { |branch| @options[:tracked].push(branch)}
    end

    def run
      case @args.shift
      when "add" then add_remote
      when "remove" then remove_remote
      else list_remotes
      end
    end

    # Adds a new remote repository
    # Usage: remote add <name> <url> [-t branch]
    # @args[0] - Name of the remote
    # @args[1] - URL of the remote repository
    # @options[:tracked] - Optional branches to track
    # Exits with status 0 on success, 128 on failure
    def add_remote
      name, url = @args[0], @args[1]
      repo.remotes.add(name, url, @options[:tracked])
      exit 0

    rescue Remotes::InvalidRemote => error
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end

    # Removes an existing remote repository
    # Usage: remote remove <name>
    # @args[0] - Name of the remote to remove
    # Exits with status 0 on success, 128 on failure
    # Note: This operation cannot be undone without manual intervention
    def remove_remote
      repo.remotes.remove(@args[0])
      exit 0
    rescue Remotes::InvalidRemote => error 
      @stderr.puts "fatal: #{ error }"
      exit 128
    end

    # Lists all configured remote repositories
    # When verbose flag is not set, displays only remote names
    # When verbose flag is set, shows fetch and push URLs for each remote
    def list_remotes
      repo.remotes.list_remotes.each { |name| list_remote(name) }
    end

    # Displays information for a single remote
    # @param name [String] The name of the remote to display
    # In verbose mode (-v flag), shows both fetch and push URLs
    # In normal mode, shows only the remote name
    # Note: Push and fetch URLs can be different in some git configurations
    def list_remote(name)
      return puts name if !@options[:verbose]

      remote = repo.remotes.get(name)

      puts "#{ name }\t#{ remote.fetch_url } (fetch)"
      puts "#{ name }\t#{ remote.push_url } (push)"
    end
  end
end