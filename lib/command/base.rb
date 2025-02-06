require "colorize"
require_relative "../pager"

module Command 
  # Base class for all tide commands
  # Provides common functionality and interface for command execution
  class Base
    # Exit status of the command
    attr_reader :status

    # Initializes a new command instance
    # @param dir [String] Working directory path
    # @param env [Hash] Environment variables
    # @param args [Array] Command line arguments
    # @param stdin [IO] Standard input stream
    # @param stdout [IO] Standard output stream
    # @param stderr [IO] Standard error stream
    def initialize(dir, env, args, stdin, stdout, stderr)
      @dir = dir
      @env = env
      @args = args
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @isatty = @stdout.isatty
    end

    # Executes the command within an exit catch block
    # This allows commands to exit early using the exit method
    # @return [void]
    def execute
      catch(:exit) { run }

      # when the current command calls exit, it waits for the pager to exit if there`s a pager active. 
      if defined? @pager
        @stdout.close_write # tell the pager there is no more input to display
        @pager.wait
        
      end
    end

    # Lazily initializes and returns the repository instance
    # @return [Repository] Repository instance for current directory
    def repo 
      @repo ||= Repository.new(Pathname.new(@dir).join('.git'))
    end

    # Expands a relative path to its absolute form
    # @param path [String] Relative or absolute path
    # @return [Pathname] Absolute path as Pathname object
    def expanded_pathname(path)
      Pathname.new(File.expand_path(path, @dir))
    end

    # Writes a string to standard output
    # @param string [String] The string to output
    # @return [void]
    def puts(string)
      @stdout.puts(string)
    rescue Errno::EPIPE
      exit 0
    end

    # Exits the command with given status
    # @param status [Integer] Exit status code (default: 0)
    # @return [void]
    def exit(status = 0)
      @status = status
      throw :exit
    end

    def setup_pager
      return if defined? @pager 
      return if !@isatty 

      @pager = Pager.new(@env, @stdout, @stderr)
      @stdout = @pager.input
    end

    def fmt(style, string)
      @isatty ? colorize(string) : string
    end

  end
end
