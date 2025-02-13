require_relative "./shared/write_commit"
require_relative "../merge/inputs"
require_relative "../merge/resolve"

module Command
  class Merge < Base 
    include WriteCommit

    def run 
      handle_abort if @options[:mode] == :abort
      handle_continue if @options[:mode] == :continue
      handle_in_progress_merge if pending_commit.in_progress?

      @inputs = ::Merge::Inputs.new(repo, Revision::HEAD, @args[0])
      repo.refs.update_ref(Refs::ORIG_HEAD, @inputs.left_oid)
      handle_merged_ancestor if @inputs.already_merged?
      handle_fast_forward if @inputs.fast_forward?

      pending_commit.start(@inputs.right_oid, @stdin.read)
      resolve_merge
      commit_merge
      exit 0
    end

    def resolve_merge
      repo.index.load_for_update
      merge = ::Merge::Resolve.new(repo, @inputs)
      merge.on_progress { |info| puts info }
      merge.execute

      repo.index.write_updates
      if repo.index.conflict?
        puts "Automatic merge failed; fix conflicts and then commit the result."
        exit 1 
      end
    end

    def commit_merge
      parents = [@inputs.left_oid, @inputs.right_oid]
      message = @stdin.read
      write_commit(parents, message)

      pending_commit.clear # If the merge runs successfully and does not exit due to conflicted index, then remove the stored merge data.
    end

    def handle_merged_ancestor
      puts "Already up to date"
      exit 0
    end

    def handle_fast_forward
      a = repo.database.short_oid(@inputs.left_oid)
      b = repo.database.short_oid(@inputs.right_oid)

      puts "Updating #{ a }..#{ b }"
      puts "Fast-forward"

      repo.index.load_for_update

      tree_diff = repo.database.tree_diff(@inputs.left_oid, @inputs.right_oid)
      migration = repo.migration(tree_diff)
      migration.apply_changes

      repo.index.write_updates
      repo.refs.update_head(@inputs.right_oid)

      exit 0
    end

    def define_options
      @options[:mode] = :run
      @parser.on("--continue") { @options[:mode] = :continue }
      @parser.on("--abort") { @options[:mode] = :abort }
    end

    def handle_continue
      repo.index.load
      resume_merge
    rescue Repository::PendingCommit::Error => error
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end

    # Deals with calling merge when one is already in progress.
    def handle_in_progress_merge
      message = "Merging is not possible because you have unmerged files"
      @stderr.puts "error: #{ message }"
      @stderr.puts CONFLICT_MESSAGE
      exit 128
    end

    def handle_abort
      repo.pending_commit.clear

      repo.index.load_for_update
      repo.hard_reset(repo.refs.read_head)
      repo.index.write_updates

      exit 0
    rescue Repository::PendingCommit::Error => error
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end

  end
end