module Command
  module WriteCommit 

    CONFLICT_MESSAGE = <<~MSG
      hint: Fix them up in the work tree, and then use 'tide add <file>'
      hint: Fix them up in the work tree, and then use 'tide add <file>'
      hint: as appropriate to mark resolution and make a commit.
      fatal: Exiting because of an unresolved conflict.
    MSG

    CHERRY_PICK_NOTES = <<~MSG
    It looks like you may be commit a cherry-pick.
    If this is not correct, please remove the file
    \t.git/CHERRY_PICK_HEAD
    and try again.
    MSG


    MERGE_NOTES = <<~MSG
    It looks like you may be committing a merge.
    If this is not correct, please remove the file
    \t.git/MERGE_HEAD
    and try again.
    MSG
    
    def write_commit(parents, message)
      tree = write_tree
      name = @env.fetch("GIT_AUTHOR_NAME")
      email = @env.fetch("GIT_AUTHOR_EMAIL")
      author = Database::Author.new(name, email, Time.now)

      commit = Database::Commit.new(parents, tree.oid, author, message)
      repo.database.store(commit)
      repo.refs.update_head(commit.oid)

      commit
    end

    def write_tree
      root = Database::Tree.build(repo.index.each_entry)
      root.traverse { |tree| repo.database.store(tree) }
      root
    end

    def pending_commit
      @pending_commit ||= repo.pending_commit
    end

    # Write a merge commit using the stored state. 
    def resume_merge(type)
      case type
      when :merge then write_merge_commit
      when :cherry_pick then write_cherr_pick_commit
      end

      exit 0
    end

    def write_merge_commit
      handle_conflicted_index
      parents = [repo.refs.read_head, pending_commit.merge_oid]
      message = compose_merge_message(MERGE_NOTES)
      write_commit(parents, message)

      pending_commit.clear
      exit 0
    end

    def write_cherr_pick_commit
      handle_conflicted_index

      parents = [repo.refs.read_head]
      message = compose_merge_message(CHERRY_PICK_NOTES)
      pick_oid = pending_commit.merge_oid(:cherry_pick)
      commit = repo.database.load(pick_oid)

      picked = Database::Commit.new(parents, write_tree.oid, commit.author, message)
      repo.database.store(picked)
      repo.refs.update_head(picked.oid)
      pending_commit.clear(:cherry_pick)
    end

    def compose_merge_message(notes=nil)
      edit_file(commit_message_path) do |editor|
        editor.puts(pending_commit.merge_message)
        editor.note(notes) if notes
        editor.puts("")
        editor.note(Commit::COMMIT_NOTES)
      end
    end

    def commit_message_path
      repo.git_path.join("COMMIT_EDITMSG")
    end

    def handle_conflicted_index
      return if !repo.index.conflict?

      message = "Committing is not possible because you have unmerged files"
      @stderr.puts "error: #{ message }."
      @stderr.puts CONFLICT_MESSAGE
      exit 128
    end

    def print_commit(commit)
      ref = repo.refs.current_ref
      info = ref.head? ? "detached HEAD" : ref.short_name

      oid = repo.database.short_oid(commit.oid)

      info.concat(" (root-commit)") if !commit.parent 
      info.concat(" #{ oid }")

      puts "[#{ info }] #{ commit.title_line }"
    end

    def define_write_commit_options 
      @options[:edit] = :auto
      @parser.on("-e", "--[no-]edit") { |value| @options[:edit] = value }

      @parser.on "-m <message>", "--message=<message>" do |message|
        @options[:message] = message
      end

      @parser.on "-F <file>", "--file=<file>" do |file|
        @options[:file] = expanded_pathname(file)
      end
    end

    def read_message
      if @options.has_key?(:message)
        "#{ @options[:message] }\n"
      elsif @options.has_key?(:file)
        File.read(@options[:file])
      end
    end

  end
end