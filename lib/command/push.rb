require_relative "../command/shared/fast_forward"
require_relative "../command/shared/send_objects"
require_relative "../command/shared/remote_client"
require_relative "../remotes"

module Command
  class Push < Base

    include FastForward
    include RemoteClient
    include SendObjects
    
    CAPABILITIES = ["report-status"]
    RECEIVE_PACK = "git-receive-pack"

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

  end
end