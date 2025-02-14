class Repository
  class Sequencer
    
    TODO = /^pick (\S+) (.*)$/
    
    def initialize(repository)
      @repo = repository
      @pathname = repository.git_path.join("sequencer")
      @todo_path = @pathname.join("todo")
      @todo_file = nil?
      @commands = []
    end

    def start 
      Dir.mkdir(@pathname)
      open_todo_file
    end

    def pick(commit)
      @commands.push(commit)
    end

    def next_command
      @commands.first
    end

    def drop_command
      @commands.shift
    end

    def open_todo_file
      return if !File.directory?(@pathname)

      @todo_file = Lockfile.new(@todo_path)
      @todo_file.hold_for_update
    end

    def dump
      return if !@todo_file

      @commands.each do |commit|
        short = @repo.database.short_oid(commit.oid)
        @todo_file.write("pick #{ short } #{ commit.title_line }")
      end

      @todo_file.commit

    end

    def load
      open_todo_file

      return if !File.file?(@todo_path)

      @commands = File.read(@todo_path).lines.map do |line|
        oid, _ = TODO.match(line).captures
        oids = @repo.database.prefix_match(oid)
        @repo.database.load(oids.first)
      end
    end

    def quit
      FileUtils.rm_rf(@pathname)
    end

  end
end