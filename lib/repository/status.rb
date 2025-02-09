require_relative "./inspector"
class Repository
  class Status

    attr_reader :changed, :index_changes, :workspace_changes, :untracked_files, :stats, :head_tree, :conflicts
    
    
    def initialize(repository) 
      @repo = repository
      @stats = {}
      @changed = SortedSet.new
      @untracked_files = SortedSet.new
      
      @index_changes = SortedHash.new
      @workspace_changes = SortedHash.new

      @conflicts = SortedHash.new

      @inspector = Inspector.new(repository)

      scan_workspace
      load_head_tree
      check_index_entries
      collect_deleted_head_files
    end

    private 

    # Records the type of change observed and also their pathnames
    # @param path [String] Path to check
    # @param type [] Type of change
    def record_change(path, set, type)
      @changed.add(path)
      set[path] = type
    end


    # Recursively scans the workspace to find untracked and modified files
    # @param prefix [String, nil] Directory prefix for recursive scanning
    # @return [void]
    def scan_workspace(prefix = nil)
      @repo.workspace.list_dir(prefix).each do |path, stat|
        if @repo.index.tracked?(path)
          @stats[path] = stat if stat.file?
          scan_workspace(path) if stat.directory?
        elsif @inspector.trackable_file?(path, stat)
          path += File::Separator if stat.directory?
          @untracked_files.add(path)
        end
      end
    end


    # Loads the whole of the head commit tree
    def load_head_tree
      @head_tree = {}

      head_oid = @repo.refs.read_head
      return if !head_oid

      commit = @repo.database.load(head_oid)
      read_tree(commit.tree)
    end

    def read_tree(tree_oid, pathname=Pathname.new(""))
      tree = @repo.database.load(tree_oid)

      tree.entries.each do |name, entry|
        path = pathname.join(name)
        if entry.tree?
          read_tree(entry.oid, path)
        else 
          @head_tree[path.to_s] = entry
        end
      end
    end

    # Checks index entries against workspace and the HEAD tree
    def check_index_entries
      @repo.index.each_entry do |entry|
        if entry.stage == 0
          check_index_against_workspace(entry)
          check_index_against_head_tree(entry)
        else 
          @changed.add(entry.path)
          @conflicts[entry.path] ||= []
          @conflicts[entry.path].push(entry.stage)
        end
       
      end  
    end


    # Checks a single index entry for modifications
    # Compares file stats and content hashes to detect changes
    # @param entry [Index::Entry] Index entry to check
    # @return [void]
    def check_index_against_workspace(entry)
      stat = @stats[entry.path]

      status = @inspector.compare_index_to_workspace(entry, stat)


      if !status
        @repo.index.update_entry_stat(entry, stat)
      else
        record_change(entry.path, @workspace_changes, status)
      end
    end


    # Compares each index entry against the entries in @head_tree to 
    # detect differences
    def check_index_against_head_tree(entry)
      item = @head_tree[entry.path]

      status = @inspector.compare_tree_to_index(item, entry)
      
      if status
        record_change(entry.path, @index_changes, status)
      end
    end

    def collect_deleted_head_files
      @head_tree.each_key do |path|
        # Change tracked_file? to tracked? to match the method used elsewhere
        unless @repo.index.tracked_file?(path)
          record_change(path, @index_changes, :deleted)
        end
      end
    end
  
   
  end
end