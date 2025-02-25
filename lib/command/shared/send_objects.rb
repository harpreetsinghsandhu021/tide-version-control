require_relative "../../rev_list"
require_relative "../../pack"

module Command
  # SendObjects module handles the network transmission of Git objects
  # by packing and sending them efficiently over a connection
  module SendObjects 

    # Sends Git objects in a packed format over a network connection
    # @param revs [Array<String>] List of revision specifications to pack and send
    # @details
    # - Uses RevList to traverse and identify required objects 
    # - Applies compression based on Git configuration
    # - Streams packed objects over the connection using Pack::Writer
    def send_packed_objects(revs)
      # Set options to include all objects and detect missing ones
      rev_opts = { :objects => true, :missing => true }
      rev_list = ::RevList.new(repo, revs, rev_opts)

      # Get compression settings from Git config
      pack_compresssion = repo.config.get(["pack", "compression"]) || repo.config.get(["core", 'compression'])

      # Configure pack writer with compression settings
      write_opts = { :compression => pack_compresssion }
      writer = Pack::Writer.new(@conn.output, repo.database, :compression => pack_compresssion, :progress => Progress.new(@stderr))

      # Write all objects from the revision list to the pack
      writer.write_objects(rev_list)
      
    end

  end
end