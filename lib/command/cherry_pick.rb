require_relative "../editor"
require_relative "../command/shared/sequencing"

module Command
  
  class CherryPick < Base
    include WriteCommit
    include Sequencing

    private

    def pick(commit)
      inputs = pick_merge_inputs(commit)
      resolve_merge(inputs)
      fail_on_conflict(inputs, commit.message) if repo.index.conflict?

      picked = Database::Commit.new([inputs.left_oid], write_tree.oid, commit.author, commit.author, commit.message)

      finish_commit(picked)
    end

    def pick_merge_inputs(commit)
      short = repo.database.short_oid(commit.oid)

      left_name = Refs::HEAD
      left_oid = repo.refs.read_head
      right_name = "#{ short }...#{ commit.title_line.strpip }"
      right_oid = commit.oid

      ::Merge::CherryPick.new(left_name, right_name, left_oid, right_oid, [commit.parent])
    end

    def merge_type
      :cherry_pick
    end

    def store_commit_sequence
      commits = RevList.new(repo, @args.reverse, :walk => false)
      commits.reverse_each { |commit| sequencer.pick(commit) }
    end

  end
end