require_relative "../remotes"
require_relative "../rev_list"

module Command
  class Fetch < Base


    include FastForward
    include RecieveObjects 
    include RemoteClient

    UPLOAD_PACK = "git-upload-pack"
    

    def define_options
      @parser.on("-f","--force") { @options[:force] = true }

      @parser.on "--upload-pack=<upload-pack>" do |uploader|
        @options[:uploader] = uploader
      end
    end

    def run 
      # Set up configuration for fetch operation
      configure
      # Initialize connection with remote using specified upload pack
      start_agent("fetch", @uploader, @fetch_url)
      # Get list of remote references
      rev_references
      # Send list of commits we want to fetch
      send_want_list
      # Receive object data from remote
      recv_objects
      # Update local ref pointers to match remote
      update_remote_refs
      # Exit with 0 if no errors, 1 if errors occurred
      exit (@errors.empty? ? 0 : 1)
    end

    def configure
      # Get remote name, defaulting to "origin" if not specified
      name = @args.fetch(0, Remotes::DEFAULT_REMOTE)
      # Load remote configuration from repo
      remote = repo.remotes.get(name)

      # Set fetch URL from remote config or command line argument
      @fetch_url = remote&.fetch_url || @args[0]
      # Set upload pack from options, remote config, or default
      @uploader = @options[:uploader] || remote&.uploader || UPLOAD_PACK
      # Set fetch specs from args or remote config
      @fetch_specs = (@args.size > 1) ? @args.drop(1) : remote&.fetch_specs
    end

    # Sends the list of the commits the local repo wants from remote.
    def send_want_list
      # Expand fetch specifications into source->target ref mappings
      @targets = Remotes::Refspec.expand(@fetch_specs, @remote_refs.keys)
      # Track unique commit IDs we want to fetch
      wanted = Set.new

      # Store local ref states
      @local_refs = {}

      @targets.each do |target, (source, _)|
        # Get current commit ID for local ref
        local_oid = repo.refs.read_ref(target)
        # Get commit ID from remote ref
        remote_oid = @remote_refs[source]

        # Skip if local and remote are already in sync
        next if local_oid == remote_oid

        # Store local ref state and add remote commit to wanted list
        @local_refs[target] = local_oid
        wanted.add(remote_oid)
      end

      # Send "want" message for each commit we need
      wanted.each { |oid| @conn.send_packet("want #{ oid }")}
      # Send empty packet to terminate want list
      @conn.send_packet(nil)

      # Exit if nothing to fetch
      exit 0 if wanted.empty?
    end

    # Sends the list of the commits the local repo already has.
    def send_have_list
      # Set options to include all commits and mark missing objects
      options = { :all => true, :missing => true }
      # Create new RevList instance to iterate through all local commits
      rev_list = ::RevList.new(repo, [], options)

      # For each local commit, send a "have" message to remote
      # This tells remote what commits we already have locally
      rev_list.each { |commit| @conn.send_packet("have #{ commit.oid }")}
      # Send "done" to indicate we've sent all our local commits
      @conn.send_packet("done")

      # Wait for remote to respond with packfile signature
      # Empty block because we're just waiting for the signature
      @conn.recv_until(Pack::SIGNATURE) {}
    end

    def recv_objects
      recv_packed_objects(Pack::SIGNATURE)
    end

    # Updates all remote references after fetching objects
    # Processes each fetched reference and attempts to update local refs
    def update_remote_refs
      @stderr.puts "From #{ @fetch_url }"

      @errors = {}
      @local_refs.each { |target, oid| attempt_ref_update(target, oid) }
    end

    # Attempts to update a single reference to its new value
    # Handles fast-forward checks and forced updates
    # @param target [String] The name of the local reference to update
    # @param old_oid [String] The current commit ID of the reference
    def attempt_ref_update(target, old_oid)
      # Get source reference and whether update is forced from refspec
      source, forced = @targets[target]

      # Get the new commit ID from remote references
      new_oid = @remote_refs[source]

      # Prepare reference names for status reporting
      ref_names = [source, target]
      # Check if update would be a fast-forward
      ff_error = fast_forward_error(old_oid, new_oid)

      # Update reference if forced or is fast-forward
      if @options[:force] || forced || ff_error == nil
        repo.refs.update_ref(target, new_oid)
      else
        # Record error if update not allowed
        error = @errors[target] = ff_error
      end

      # Report status of the reference update
      report_ref_update(ref_names, error, old_oid, new_oid, ff_error == nil)
    end

  end
end