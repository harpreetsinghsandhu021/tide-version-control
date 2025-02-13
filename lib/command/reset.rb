module Command
  class Reset < Base
    
    def run 
      @head_oid = repo.refs.read_head

      select_commit_oid

      repo.index.load_for_update
      reset_files
      repo.index.write_updates

      exit 0
    end

    def reset_path(pathname)
      listing = repo.database.load_tree_list(@commit_oid, pathname)
      repo.index.remove(pathname)

      listing.each do |path, entry|
        repo.index.add_from_db(path, entry)
      end
    end

    def select_commit_oid
      # Fetch the first argument passed to the commannd, defaulting to "HEAD".
      revision = @args.fetch(0, Revision::HEAD)

      # Attempt to resolve the provided revision (branch name, tag, commit hash, etc.) into a valid commit OID.
      @commit_oid = Revision.new(repo, revision).resolve

      # Remove the First argument from @args since it`s been processed.
      @args.shift

    rescue Revision::InvalidObject
      @commit_oid = repo.refs.read_head # Use current HEAD as fallback.
    end

    def define_options
      @options[:mode] = :mixed
      @parser.on("--soft") { @options[:mode] = :soft }
      @parser.on("--mixed") { @options[:mode] = :mixed }
      @parser.on("--hard") { @options[:mode] = :hard }
    end

    def reset_files
      # If the reset mode is "soft", do nothing. In a soft reset, only the HEAD pointer is moved.
      return if @options[:mode] == :soft
      return repo.hard_reset(@commit_oid) if @options[:mode] == :hard

      if @args.empty?
        # 1. Clear the entire index. This removes all files from the staging area.
        repo.index.clear!
         # 2. Update the index with the contents of the selected commit's tree.
        reset_path(nil) # Passing 'nil' to reset_path updates the entire working tree
      else
        @args.each { |path| reset_path(Pathname.new(path)) }
      end
    end

  end
end