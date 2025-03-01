require_relative "./shared/recieve_objects"
require_relative "./shared/remote_agent"


module Command
  class RecievePack < Base
    
    include RecieveObjects
    include RemoteAgent
    include FastForward

    CAPABILITIES = ["no-thin", "report-status", "delete-refs"]

    def run 
      accept_client("receive-pack", CAPABILITIES)

      send_references
      recv_update_requests
      recv_objects 
      update_refs

      exit 0
    end

    def recv_update_requests
      # Initialize hash to store reference update requests
      @requests = {}

      # Receive update requests until empty packet
      # Format: <old-oid> <new-oid> <ref-name>
      @conn.recv_until(nil) do |line|
        # Split line into old commit ID, new commit ID, and reference name
        old_oid, new_oid, ref = line.split(/ +/)
        # Convert zero OIDs to nil and store in requests hash
        # nil old_oid means new ref, nil new_oid means deletion
        @requests[ref] = [old_oid, new_oid].map { |oid| zero_to_nil(oid) } 
      end
    end

    def zero_to_nil(oid)
      oid == ZERO_OID ? nil : oid
    end

    def recv_objects
      # Track any errors during unpacking
      @unpack_error = nil

      unpack_limit = repo.config.get(["recieve", "unpackLimit"])
      recv_packed_objects(unpack_limit) if @requests.values.any?(&:last)
      report_status("unpack ok")
    rescue => error
      # Store error and report failure if anything goes wrong
      @unpack_error = error
      report_status("unpack #{ error.message }")
    end

    def report_status(line)
      @conn.send_packet(line) if @conn.capable?("report-status")
    end

    def update_refs
      # Process each reference update request
      # ref: reference name
      # old: current commit ID (nil for new refs)
      # new: target commit ID (nil for deletions)
      @requests.each { |ref, (old, new)| update_ref(ref, old, new)}
      # Send empty status to indicate all updates are complete
      report_status(nil)
    end

    def update_ref(ref, old, new)
      # If there was an error during unpacking, report failure
      return report_status("ng #{ ref } unpacker error") if @unpack_error

      # validates the update, throws an error if the update violates
      # the repository`s configuration
      validate_update(ref, old, new)

      # Attempt atomic update of reference
      # Will fail if current value doesn't match old value
      repo.refs.compare_and_swap(ref, old, new)
      # Report success for this reference
      report_status("ok #{ ref }")
    rescue => error
      # Report specific error if update failed
      # Format: ng <ref-name> <error-message>
      report_status("ng #{ ref } #{ error.message }")
    end

    def validate_update(ref, old_oid, new_oid)
      raise "funny refname" if !Revision.valid_ref?(ref)
      raise "missing necessary objects" if new_oid && !repo.database.has?(new_oid)

      if repo.config.get(["recieve", "denyDeletes"])
        raise "deletion prohibited" if !new_oid
      end

      if repo.config.get(["recieve", "denyNonFastForwards"])
        raise "non-fast-forward" if fast_forward_error(old_oid, new_oid)
      end
      
      return if !repo.config.get(["core", "bare"]) == false && 
      repo.refs.current_ref.path == ref

      if repo.config.get(["recieve", "denyCurrentBranch"]) != false
        raise "branch is currently checked out" if new_oid
      end

      if repo.config.get(["recieve", "denyDeleteCurrent"]) != false
        raise "deletion of the current branch prohibited" if !new_oid
      end

    end

    

  end
end