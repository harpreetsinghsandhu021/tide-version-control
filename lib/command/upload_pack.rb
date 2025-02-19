require_relative "./shared/remote_agent"


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
    
    # Here, On Remote side, we read the want lines from the client.
    # We read until we get a flush packet.
    def recv_want_list
      @wanted = recv_oids("want", nil)
      exit 0 if @wanted.empty
    end

    def recv_oids(prefix, terminator)
      pattern = /^#{ prefix } ([0-9a-f]+)$/
      result = Set.new

      @conn.recv_until(terminator) do |line|
        result.add(pattern.match(line)[1])
      end

      result
    end

    # Recieves have commit IDs.
    def recv_have_list
      @remote_has = recv_oids("have", "done")
      @conn.send_packet("NAK")
    end

    
    def send_objects
      revs = @wanted + @remote_has.map { |oid| "^#{ oid }"}
      send_packed_objects(revs)
    end

  end
end