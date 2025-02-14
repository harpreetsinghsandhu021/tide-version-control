require_relative "../editor"

module Command
  
  class CherryPick < Base
    include WriteCommit

    CONFLICT_NOTES = <<~MSG
      after resolving the conflicts, mark the corrected paths
      with 'tide add <paths>' or 'tide rm <paths>' 
      and commit the result with 'tide commit'
    MSG

    def run 
      case @options[:mode]
      when :continue then handle_continue
      when :abort then handle_abort
      when :quit then handle_quit
      end

      sequencer.start
      store_commit_sequence
      resume_sequencer

      exit 0
    end

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

    def resolve_merge(inputs)
      repo.index.load_for_update
      ::Merge::Resolve.new(repo, inputs).execute
      repo.index.write_updates
    end

    def finish_commit(commit)
      repo.database.store(commit)
      repo.refs.update_head(commit.oid)
      print_commit(commit)
    end

    def fail_on_conflict(inputs, message)
      sequencer.dump
      pending_commit.start(inputs.right_oid, merge_type)

      edit_file(pending_commit.message_path) do |editor|
        editor.puts(message)
        editor.puts("")
        editor.note("Conflicts:")
        repo.index.conflict_paths.each { |name| editor.note("\t#{ name }")}
        editor.close
      end

      @stderr.puts "error: could not apply #{ inputs.right_name }"
      CONFLICT_NOTES.each_line { |line| @stderr.puts "hint: #{ line }"}
  
      exit 1
    end

    def merge_type
      :cherry_pick
    end

    def define_options
      @options[:mode] = :run
      @parser.on("--continue") { @options[:mode] = :continue}
      @parser.on("--abort") { @options[:mode] = :abort}
      @parser.on("--quit") { @options[:mode] = :quit}
    end

    def handle_continue
      repo.index.load
      write_cherr_pick_commit if pending_commit.in_progress?

      sequencer.load
      sequencer.drop_command
      resume_sequencer

      exit 0
    rescue Repository::PendingCommit::Error => error
      @stderr.puts "fatal: #{ error.message }"

      exit 128
    end

    def sequencer
      @sequencer ||= Repository::Sequencer.new(repo)
    end

    def store_commit_sequence
      commits = RevList.new(repo, @args.reverse, :walk => false)
      commits.reverse_each { |commit| sequencer.pick(commit) }
    end

    def resume_sequencer
      loop do 
        break if commit = sequencer.next_command
        pick(commit)
        sequencer.drop_command
      end

      sequencer.exit
      exit 0
    end

    def handle_quit
      pending_commit.clear(merge_type) if pending_commit.in_progress?
      sequencer.quit

      exit 0
    end

    def handle_abort
      pending_commit.clear(merge_type) if pending_commit.in_progress?
      repo.index.load_for_update

      begin 
        sequencer.abort
      rescue => error
        @stderr.puts "warning: #{ error.message }"
      end

      repo.index.write_updates
      exit 0

    end

  end
end