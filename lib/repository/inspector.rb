
class Repository
  class Inspector
    
    def initialize(repository)
      @repo = repository
    end

     # Determines if a file should be tracked
    # @param path [String] Path to check
    # @param stat [File::Stat] File statistics
    # @return [Boolean] true if file should be tracked
    def trackable_file?(path, stat)
      return false if !stat

      return !@repo.index.tracked_file?(path) if stat.file?
      return false if !stat.directory?

      items = @repo.workspace.list_dir(path)
      files = items.select { |_, item_stat| item_stat.file? }
      dirs = items.select { |_, item_stat| item_stat.directory? }

      # Check if any files or directories should be tracked
      [files, dirs].any? do |list|
        list.any? do |item_path, item_stat|
         trackable_file?(item_path, item_stat)
        end
      end
    end

    def compare_index_to_workspace(entry, stat)
      return :untracked if !entry
      return :deleted  if !stat
      return :modified if !entry.stat_match?(stat)
      return nil if entry.times_match?(stat)

      data = @repo.workspace.read_file(entry.path)
      blob = Database::Blob.new(data)
      oid = @repo.database.hash_object(blob)

      if entry.oid != oid
        :modified
      end
    end

    def compare_tree_to_index(item, entry)
      return nil unless item or entry
      return :added if !item
      return :deleted if !entry

      if entry.mode != item.mode or entry.oid != item.oid
        :modified
      end
    end

  end
end