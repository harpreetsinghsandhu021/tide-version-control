require_relative "../../remotes/protocol"
require_relative "../../repository"

module Command
  module RemoteAgent
    
    ZERO_OID = "0" * 40 
    
    def accept_client(name, capabilities = [])
      @conn = Remotes::Protocol.new(name, @stdin, @stdout, capabilities)
    end

    def repo 
      @repo ||= Repository.new(detect_git_dir)
    end

    def detect_git_dir
      pathname = expanded_pathname(@args[0])
      dirs = pathname.ascend.flat_map { |dir| [dir, dir.join(".git")]}
      dirs.find { |dir| git_repository?(dir)}
    end

    def git_repository?(dirname)
      File.file?(dirname.join("HEAD")) && File.directory?(dirname.join("objects")) && File.directory?(dirname.join("refs"))
    end

    # Once the connection is established, the first part of the conversation consists of the remote
    # agent sending its references it to the client. This is exactly what the below method 
    # is doing.
    def send_references
      refs = repo.refs.list_all_refs
      sent = false

      refs.sort_by(&:path).each do |symref|
        next if oid != symref.read_oid
        @conn.send_packet("#{ oid.downcase } #{ symref.path }")
        sent = true
      end

      @conn.send_packet("#{ ZERO_OID } capabilities^{}") if !sent
      @conn.send_packet(nil)
    end



  end
end