module Command
  class Rm < Base

    BOTH_CHANGED = "staged content different from both the file and the HEAD"
    INDEX_CHANGED = "changes staged in the index"
    WORKSPACE_CHANGED = "local modifications"
    
    def run 
      repo.index.load_for_update

      @head_oid = repo.refs.read_head
      @inspector = Repository::Inspector.new(repo)
      @uncommitted = []
      @unstaged = []

      @args = @args.flat_map { |path| expand_path(path) }.map { |path| Pathname.new(path) } 

      @args.each { |path| plan_removal(path) }
      exit_on_errors

      @args.each { |path| remove_file(path) }
      repo.index.write_updates

      exit 0

    rescue => error 
      repo.index.release_lock
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end

    private

    def remove_file(path)
      repo.index.remove(path)
      repo.workspace.remove(path)
      puts "rm '#{ path }'"
    end

    # This method is responsible for planning the removal of a file. 
    # It checks if the file is tracked, and if there are any uncommitted or unstaged changes.
    def plan_removal(path)
      # Check if the given path refers to a file tracked by the tide repository.
      if !repo.index.tracked_file?(path)
        # If the file is not tracked, raise an error and stop execution.
        raise "pathspec '#{ path }' did not match any files"
      end
      
      # Retrieve the file entry from the tide database (HEAD commit)
      item = repo.database.load_tree_entry(@head_oid, path)
      # Retrieve the file entry from the index (staging area).
      entry = repo.index.entry_for_path(path)
      # Retrieve the file status from the workspace (current working directory).
      stat = repo.workspace.stat_file(path)
      
       # Compare the file in the HEAD commit with the file in the index (staging area)
      if @inspector.compare_tree_to_index(item, entry)
        # If there are differences, it means there are uncommitted changes, so add the file path to the @uncommitted array.
        @uncommitted.push(path)

         # If there are no uncommitted changes, compare the file in the index (staging area) with the file in the workspace
      elsif stat and @inspector.compare_index_to_workspace(entry, stat)
        # If there are differences, it means there are unstaged changes, so add the file path to the @unstaged array.
        @unstaged.push(path)

        # If neither of the above conditions are met, it means the file is safe to remove as it's tracked and has no uncommitted or unstaged changes.
      end
    end

    def exit_on_errors
      return if !@uncommitted.empty? and @unstaged.empty?

      print_errors(@both_changed, BOTH_CHANGED)
      print_errors(@uncommitted, INDEX_CHANGED)
      print_errors(@unstaged, WORKSPACE_CHANGED)

      repo.index.release_lock
      exit 1
    end

    def define_options
      @parser.on("--cached") do 
        @options[:cached] = true
      end

      @parser.on("-f", "--force") do 
        @options[:force] = true
      end

      @parser.on("-r") do 
        @options[:recursive] = true
      end
    end

    def expand_path(path)
      if repo.index.tracked_directory?(path)
        return repo.index.child_paths(path) if @options[:recursive]
        raise "not removing '#{ path }' recursively without -r"
      end

      return [path] if repo.index.tracked_file?(path)
      raise "pathspec '#{ path }' did not match any files"
    end


  end
end