module Command 
  class Revert < Base
    
    include Sequencing
    include WriteCommit
    
    private

    def merge_type
      :revert
    end

    def store_commit_sequence
      commits = RevList.new(repo, @args, :walk => false)
      commits.each { |commit| sequencer.revert(commit) }  
    end

    def revert(commit)
      # Get the merge inputs required for reverting the commit
      # This includes the commit to revert and the current HEAD
      inputs = revert_merge_inputs(commit)

      # Generate a default revert commit message based on the commit being reverted
      message = revert_commit_message(commit)

      # Attempt to merge the changes, effectively undoing the commit
      # This creates a reverse patch of the original commit
      resolve_merge(inputs)

      # If there are merge conflicts, abort the revert operation
      # and notify the user about the conflicts
      fail_on_conflict(inputs, message) if repo.index.conflict?

      # Get the current author information for the revert commit
      author = current_author

      # Allow the user to edit the generated revert commit message
      # This step might open an editor for message modification
      message = edit_revert_message(message)

      # Create a new commit object
      picked = Database::Commit.new([inputs.left_oid], write_tree.oid, author, author, message)

      # Finalize the revert commit and update the repository state
      finish_commit(picked)
    end

    def revert_merge_inputs(commit)
      short = repo.database.short_oid(commit.oid)

      left_name = Refs::HEAD
      left_oid = repo.refs.read_head

      right_name = "parent of #{ short }... #{ commit.title_line.strip }"
      right_oid = commit.parent

      ::Merge::CherryPick.new(left_name, right_name, left_oid, right_oid, [commit.oid])
    end

    def revert_commit_message(commit)
      <<~MESSAGE
        Revert "#{ commit.title_line.strip }

        This reverts commit #{ commit.oid }
      MESSAGE
    end

    def edit_revert_message(message)
      edit_file(commit_message_path) do |editor|
        editor.puts(message)
        editor.puts("")
        editor.note(Commit::COMMIT_NOTES)
      end  
    end

  end
end