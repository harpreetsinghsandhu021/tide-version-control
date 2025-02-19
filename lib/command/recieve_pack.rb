require_relative "./shared/recieve_objects"
require_relative "./shared/remote_agent"


module Command
  class RecievePack < Base
    
    include RecieveObjects
    include RemoteAgent

    CAPABILITIES = ["no-thin", "report-status", "delete-refs"]

    def run 
      accept_client("receive-pack", CAPABILITIES)

      send_references
      recv_update_requests
      recv_objects 
      update_refs

      exit 0
    end

  end
end