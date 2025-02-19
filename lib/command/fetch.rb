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
      configure
      start_agent("fetch", @uploader, @fetch_url)
      rev_references
      send_want_list
      recv_objects
      update_remote_refs
      exit (@errors.empty? ? 0 : 1)
    end

    def configure
      name = @args.fetch(0, Remotes::DEFAULT_REMOTE)
      remote = repo.remotes.get(name)

      @fetch_url = remote&.fetch_url || @args[0]
      @uploader = @options[:uploader] || remote&.uploader || UPLOAD_PACK
      @fetch_specs = (@args.size > 1) ? @args.drop(1) : remote&.fetch_specs
    end

  end
end