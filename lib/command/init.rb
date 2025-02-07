require "pathname"
require_relative "./base"

module Command 
  class Init < Base
    DEFAULT_BRANCH = "main"
    def run
      # Resolving the path relative to cwd and wrap in Pathname Object
      path = @args.fetch(0, @dir)
      root_path = expanded_pathname(path)
      git_path = root_path.join('.git') # contruct the path for the .git directory

      # Create two directories objects and refs
      ["objects", "refs/heads"].each do |dir|
        begin
          FileUtils.mkdir_p(git_path.join(dir))
        rescue Errno::EACCES => error
          @stderr.puts "Fatal : #{error.message}"
          exit 1
        end
      end

      refs = Refs.new(git_path)
      path = File.join("refs", "heads", DEFAULT_BRANCH)
      refs.update_head("ref: #{ path }")

      puts "Intialized Empty Tide repository in #{git_path}"
      exit 0
    end
  end
end