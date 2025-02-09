
module Merge
  class Resolve
    
    def initialize(repository, inputs)
      @repo = repository
      @inputs = inputs
    end

    def execute
      prepare_tree_diffs

      migration = @repo.migration(@clean_diff)
      migration.apply_changes

      add_conflicts_to_index
      write_untracked_files

    end

    # Detects any conflicts b/w merged branches, and building a tree diff that can be applied to the index.
    def prepare_tree_diffs
      base_oid = @inputs.base_oids.first

      # Calculates two tree diffs
      @left_diff = @repo.database.tree_diff(base_oid, @inputs.left_oid) # tree diff b/w merge base and left commit i.e (the current HEAD, whose tree is in the index).
      @right_diff = @repo.database.tree_diff(base_oid, @inputs.right_oid) # tree diff b/w merge base and right commit. 

      @clean_diff = {}
      @conflicts = {}
      @untracked = {}

      # Iterates over the right tree diff to check if it modifies any of the same files as the left tree diff.
      @right_diff.each do |path, (old_item, new_item)|
        file_dir_conflict(path, @left_diff, @inputs.left_name) if new_item
        same_path_conflict(path, old_item, new_item)
      end

      @left_diff.each do |path, (_, new_item)|
        file_dir_conflict(path, @right_diff, @inputs.right_name) if new_item
      end

    end

    # Check If the left diff also modifies the same file, and if so, attempt to reconcile those changes.
    def same_path_conflict(path, base, right)
      # If the left diff does not contain the given path, then there is no conflict to report. 
      # that means we can put right commit`s version of the file into the index.
      if !@left_diff.has_key?(path)
        @clean_diff[path] = [base, right]
        return
      end

      left = @left_diff[path][1] # If there is an entry in the left diff for this path, then we fetch its post-image.
      # Both sides have changed the path but they've both changed it to have the same content i.e the right commit's verion 
      # is the same as that in HEAD. so, the index for the path does not need changing at all, and we can return right away.
      return if left == right 

      # Reaching here means both sides of the merge have changed the path in different ways.
      # In this case, we need to build some new Entry object that somehow represents both their contents, so we can slot 
      # it into the cleaned diff and migration can put this combined version into the workspace.

      log "Auto-merging #{ path }" if left and right

      # The below methods will return the merged value of each field, and a boolean indicating whether indicating 
      # whether they merged cleanly.
      oid_ok, oid = merge_blobs(base&.oid, left&.oid, right&.oid)
      mode_ok, mode = merge_modes(base&.mode, left&.mode, right&.mode)

      # Put the new entry in the clean diff with left as the pre-image so it applies against the current index.
      @clean_diff[path] = [left, Database::Entry.new(oid, mode)]
      # Put the trio [base, left, right] to the list of conflicts if either value did not merge cleanly.
      @conflicts[path] = [base, left, right] if !(oid_ok and mode_ok)
    end

    # Perform a three way merge of the inputs.
    def merge3(base, left, right)
      # Only one of the inputs to this method can be nil, and we only invoke it if both branches have changed a certain path.
      
      # If left is nil, that means the file was deleted in the left branch and modified in the right, and so this is a 
      # conflict but we can put the right commit's version into the workspace. and vice versa. 
      return [false, right] if !left 
      return [false, left] if !right

      # When merging each ind. property, either side might be equal to the base value.
      # If left is equal to base, or left and right are same, then this value can be successfully merged 
      # into right commit`s value
      if left == base || left == right
        [true, right]
      else
        [true, left]
      end
    end

      def merge_blobs(base_oid, left_oid, right_oid)
        result = merge3(base_oid, left_oid, right_oid)
        return result if result

        blob = Database::Blob.new(merged_data(left_oid, right_oid))
        @repo.database.store(blob)
        [false, blob.oid]
      end

      def merged_data(left_oid, right_oid)
        left_blob = @repo.database.load(left_oid)
        right_blob = @repo.database.load(right_oid)

        [
          "<<<<<<< #{ @inputs.left_name }\n", 
          left_blob.data, 
          "=======\n", 
          right_blob.data, 
          ">>>>>> #{ @inputs.right_name }\n"
        ].join("")
      end

      def merge_modes(base_mode, left_mode, right_mode)
        merge3(base_mode, left_mode, right_mode) || [false, left_mode]
      end

      # Evict the stage-0 entries from the workspace that has conflicts in them but were also stored in clean_diff
      # and replace them with conflict entries
      def add_conflicts_to_index
        @conflicts.each do |path, items|
          @repo.index.add_conflict_set(path, items)
        end
      end

      # Handles conflicts where a file in one branch might be modified, while a directory with the same name 
      # exists in the other branch, or vice-versa.
      def file_dir_conflict(path, diff, name)
        # For every parent of the pathname, check whether the given diff contains a post-image for that directory.
        path.dirname.ascend do |parent|
          old_item, new_item = diff[parent]

          # If the 'diff' has an entry for the current 'parent' path and it has a 'new_item' (meaning it was modified), 
          # we've found a potential file/directory conflict. 
          next if !new_item

          #  Construct a conflict entry depending on whether the conflict is coming from the left or right branch. 
          #  A conflict entry contains the base version (old_item) and either the left or right version (new_item) 
          #  depending on which branch caused the conflict
          @conflicts[parent] = case name 
          when @inputs.left_name then [old_item, new_item, nil]
          when @inputs.right_name then [old_item, nil, new_item]
          end

          @clean_diff.delete(parent) # As this is a conflict, remove this path from the list of non-conflicting changes
          rename = "#{ parent }~#{ name }" # Rename the conflicting directory so that it does not clash with the conflicting file.
          # Since the renamed directory will not be present in the index, it will show up as an untracked file in the final result.
          @untracked[rename] = new_item

          log "Adding #{ path }" if !diff[path]
          log_conflict(parent, rename)

        end
      end

    

      def write_untracked_files
        @untracked.each do |path, item|
          blob = @repo.database.load(item.oid)
          @repo.workspace.write_file(path, blob.data)
        end
      end
      
      # Simply stores off the given block, so that the internals of the class
      # can invoke it and thereby pipe log information back to the caller.
      def on_progress(&block)
        @on_progress = block   
      end

      private 

      def log(message)
        @on_progress&.call(message)
      end


      # CONFLICT REPORTING

      # Decides what type of message to emit, based on which versions are present in
      # the named conflict set.
      def log_conflict(path, rename=nil)
        base, left, right = @conflicts[path]

        if left && right
          log_left_right_conflict(path)
        elsif base && (left || right)
          log_modify_delete_conflict(path, rename)
        else
          log_file_directory_conflict(path, rename)
        end
      end

      def log_left_right_conflict(path)
        type = @conflicts[path][0] ? "content" : "add/add"
        log "CONFLICT (#{ type }): Merge conflict in #{ path }"
      end

      def log_modify_delete_conflict(path, rename)
        deleted, modified = log_branch_names(path)

        rename = rename ? " at #{ rename }" : ""

        log "CONFLICT (modify/delete): #{ path } " + 
        "deleted in #{ deleted } and modified in #{ modified }." + 
        "Version #{ modified } of #{ path } left in tree at #{ rename }"
      end

      # Returns the names of two merged branches from the inputs object, swapping their order
      # depending on whether the conflict set for the path contains an entry from the left or right commit.
      def log_branch_names(path)
        a, b = @inputs.left_name, @inputs.right_name
        @conflicts[path][1] ? [b, a] : [a, b]
      end

      def log_file_directory_conflict(path, rename)
        type = @conflicts[path][1] ? "file/directory" : "directory/file"
        branch, _ = log_branch_names(path)

        log "CONFLICT (#{ type }): There is a directory " +
        "with name #{ path } in #{ branch }. " + 
        "Adding #{ path } as #{ rename }"
      end

  end
end