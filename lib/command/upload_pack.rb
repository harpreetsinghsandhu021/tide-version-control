
module Command
  class UploadPack < Base

    include RemoteAgent
    include SendObjects

    def run 
      accept_client("upload-pack")

      send_references
      recv_want_list
      recv_have_list
      send_objects

      exit 0
    end
    
  end
end