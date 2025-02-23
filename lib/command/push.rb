require_relative "../command/shared/fast_forward"
require_relative "../command/shared/send_objects"
require_relative "../command/shared/remote_client"
require_relative "../remotes"
require_relative "../revision"


module Command
  class Push < Base

    include FastForward
    include RemoteClient
    include SendObjects
    
    CAPABILITIES = ["report-status"]
    RECEIVE_PACK = "git-receive-pack"

    UNPACK_LINE = /^unpack (.+)$/
    UPDATE_LINE = /^(ok|ng) (\S+)(.*)$/

    def define_options
      @parser.on("-f", "--force") { @options[:force] = true}
      @parser.on "--receive-pack=<receive-pack>" do |reciever|
        @options[:reciever] = reciever
      end
    end

    def run 
      configure 
      start_agent("push", @reciever, @push_url, CAPABILITIES)

      recv_references
      send_update_requests
      send_objects
      print_summary
      recv_report_status

      exit (@errors.empty? ? 0 : 1)
    end

    def configure 
      name = @args.fetch(0, Remotes::DEFAULT_REMOTE)
      remote = repo.remote.get(name)

      @push_url = remote&.push_url || @args[0]
      @fetch_specs = remote&.fetch_specs || []

      @receiver = @options[:receiver] || remote&.receiver || RECEIVE_PACK
      @push_specs = (@args.size > 1) ? @args.drop(1) : remote&.push_specs

    end

    def send_update_requests
      # Initialize storage for update operations and errors
      @updates = {}
      @errors = []

      # Get sorted list of all local references
      local_refs = repo.refs.list_all_refs.map(&:path).sort
      # Expand push specifications into source->target mappings
      # This maps local refs to their remote destination refs
      targets = Remotes::Refspec.expand(@push_specs, local_refs)

      # Process each target reference and its source mapping
      targets.each do |target, source, forced|
        # Determine if update is valid and collect update information
        select_update(target, source, forced)
      end

      # Send update requests for each valid reference update
      # Format: old-SHA new-SHA ref-name
      @updates.each { |ref, (*, old, new)| send_update(ref, old, new) }
      # Send empty packet to terminate update request list
      @conn.send_packet(nil)
    end

    # Handle branch deletion case if no source is specified
    def select_update(target, source, forced)
      return select_deletion(target) if !source

      # Get current commit ID from remote for this target reference
      old_oid = @remote_refs[target]
      # Resolve the new commit ID from our local source reference
      new_oid = Revision.new(repo, source).resolve

      # Skip if there's no actual change in commit IDs
      return if old_oid == new_oid

      # Check if update would be a fast-forward operation
      ff_error = fast_forward_error(old_oid, new_oid)

      if @options[:force] || forced || ff_error == nil
        # Store update if forced or is fast-forward:
        # - source: local ref name
        # - ff_error: any fast-forward error (nil if valid)
        # - old_oid: current remote commit
        # - new_oid: new commit to push
        @updates[target] = [source, ff_error, old_oid, new_oid]
      else
        # Record error if update not allowed
        # Track both reference names and the error message
        @errors.push([[source, target], ff_error])
      end
    end

    def select_deletion(target)
      # Check if remote supports reference deletion capability
      if @conn.capable?("delete-refs")
        # Schedule reference for deletion by setting new_oid to nil
        # Format: [source, ff_error, old_oid, new_oid]
        # - source: nil (no source for deletion)
        # - ff_error: nil (no ff check needed for deletion)
        # - old_oid: current remote commit ID
        # - new_oid: nil (indicates deletion)
        @updates[target] = [nil, nil, @remote_refs[target], nil]
      else
        # Record error if remote doesn't support reference deletion
        # Format: [[source, target], error_message]
        @errors.push([[nil, target], 'remote does not support deleting refs'])
      end
    end

    def send_update(ref, old_oid, new_oid)
      old_oid = nil_to_zero(old_oid)
      new_oid = nil_to_zero(new_oid)

      @conn.send_packet("#{ old_oid } #{ new_oid } #{ ref }")
    end

    def nil_to_zero(oid)
      oid == nil ? ZERO_OID : oid
    end

    def send_objects
      # Get list of all new commit IDs we're pushing
      revs = @updates.values.map(&:last).compact
      # Skip if no new objects to send
      return if revs.empty?

      # Add negative refs for all remote commits
      # This tells pack builder to exclude objects the remote already has
      revs += @remote_refs.values.map { |oid| "^#{ oid }"}

      # Send all new objects in packed format
      send_packed_objects(revs)
    end

    def print_summary
      if @updates.empty? && @errors.empty?
        @stderr.puts "Everything up-to-date"
      else
        @stderr.puts "To #{ @push_url }"
        @errors.each { |ref_names, error| report_ref_update(ref_names, error)}
      end
    end

    def recv_report_status
      # Skip if either:
      # - Remote doesn't support status reporting
      # - No updates were requested
      return unless @conn.capable?("report-status") && !@updates.empty?

      # Parse remote's unpack status line
      # Format: "unpack ok" or "unpack <error-message>"
      unpack_result = UNPACK_LINE.match(@conn.recv_packet)[1]

      # Show error if remote couldn't unpack our objects
      unless unpack_result == "ok"
        @stderr.puts "error: remote unpack failed: #{ unpack_result }"
      end

      # Process individual ref update status messages
      @conn.recv_until(nil) { |line| handle_status(line) }
    end

    def handle_status(line)
      # Parse status line with format: "<ok|ng> <ref-name> [error-message]"
      return unless match = UPDATE_LINE.match(line)

      # Extract components from status line
      status = match[1]     # Success ("ok") or failure ("ng")
      ref = match[2]        # Name of reference that was updated
      error = status == "ok" ? nil : match[3].strip  # Error message if failed

      # Track any failed updates for summary
      @errors.push([ref, error]) if error
      # Display status of this update
      report_update(ref, error)

      # If update succeeded, update any associated fetch tracking refs
      targets = Remotes::Refspec.expand(@fetch_specs, [ref])
      targets.each do |local_ref, (remote_ref, _)|
        # Get new value we attempted to push
        new_oid = @updates[remote_ref].last
        # Update local tracking ref if remote update succeeded
        repo.refs.update_ref(local_ref, new_oid) unless error
      end
    end

    def report_update(target, error)
      # Get stored update information:
      # source: local ref name
      # ff_error: any fast-forward error
      # old_oid: previous commit ID
      # new_oid: new commit ID
      source, ff_error, old_oid, new_oid = @updates[target]
      # Prepare ref names for display
      ref_names = [source, target]
      # Generate status message with format and commit range
      report_ref_update(ref_names, error, old_oid, new_oid, ff_error == nil)
    end


  end
end