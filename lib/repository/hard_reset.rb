
class Repository
  class HardReset

    def initialize(repo, oid)
      @repo = repo
      @oid = oid
    end

    def execute
      # Calculate the status (differences) between the target commit and the current state.
      @status = @repo.status(@oid)
      
      # Get a list of files that have changed between the target commit and the current state.
      changed = @status.changed.map { |path| Pathname.new(path) }

      # Reset each changed file to its state in the target commit.
      changed.each { |path| reset_path(path)}
    end

    def reset_path(path)
      @repo.index.remove(path) # Remove the file from the staging area.
      @repo.workspace.remove(path) # Remove the file from the working directory.

      # Get the entry for the file from the target commit`s tree.
      entry = @status.head_tree[path.to_s]
      return if !entry


      blob = @repo.database.load(entry.oid)
      # Write the blob from the database using the entry's oid.
      @repo.workspace.write_file(path, blob.data, entry.mode, true)

      stat = @repo.workspace.stat_file(path) # Get file`s stat information.
      
      # Add the file back to the staging area with its original OID and stat information.
      @repo.index.add(path, entry.oid, stat) 
    end

  end
end