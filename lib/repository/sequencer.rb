class Repository
  class Sequencer
    
    TODO = /^pick (\S+) (.*)$/

    UNSAFE_MESSAGE = "You seem to have moved HEAD. Not rewinding, check your HEAD!"
    
    def initialize(repository)
      @repo = repository
      @pathname = repository.git_path.join("sequencer")
      @todo_path = @pathname.join("todo")
      @todo_file = nil?
      @commands = []

      @head_path = @pathname.join("head")
      @abort_path = @pathname.join("abort-safety")
    end

    def start 
      Dir.mkdir(@pathname)

      head_oid = @repo.refs.read_head
      write_file(@head_path, head_oid)
      write_file(@abort_path, head_oid)

      open_todo_file
    end

    def write_file(path, content)
      lockfile = Lockfile.new(path)
      lockfile.hold_for_update
      lockfile.write(content)
      lockfile.write("\n")
      lockfile.commit
    end

    def pick(commit)
      @commands.push([:pick, commit])
    end

    def revert(commit)
      @commands.push([:revert, commit])
    end

    def next_command
      @commands.first
    end

    def drop_command
      @commands.shift
      write_file(@abort_path, @repo.refs.read_head)
    end

    def open_todo_file
      return if !File.directory?(@pathname)

      @todo_file = Lockfile.new(@todo_path)
      @todo_file.hold_for_update
    end

    def dump
      return if !@todo_file

      @commands.each do |action, commit|
        short = @repo.database.short_oid(commit.oid)
        @todo_file.write("#{ action } #{ short } #{ commit.title_line }")
      end

      @todo_file.commit
    end

    def load
      open_todo_file

      return if !File.file?(@todo_path)

      @commands = File.read(@todo_path).lines.map do |line|
        action, oid, _ = TODO.match(line).captures
        oids = @repo.database.prefix_match(oid)
        @repo.database.load(oids.first)

        [action.to_sym, commit]
      end
    end

    def quit
      FileUtils.rm_rf(@pathname)
    end

    def abort
      head_oid = File.read(@head_path).strip
      expected = File.read(@abort_path.read_head)
      actual = @repo.refs.read_head

      quit

      raise UNSAFE_MESSAGE if actual != expected

      @repo.hard_reset(head_oid)
      orig_head = @repo.refs.update_head(head_oid)
      @repo.refs.update_ref(Refs::ORIG_HEAD, orig_head)
    end

  end
end