require "open3"
require "shellwords"
require "uri"

require_relative "../../remotes/protocol"

module Command
  # RemoteClient module provides functionality for establishing and managing
  # connections with remote Git processes/agents
  module RemoteClient
    # Initiates a connection with a remote agent process
    # @param name [String] The identifier for the agent
    # @param program [String] The command/program to execute
    # @param url [String] The URL to connect to
    # @param capabilities [Array] Optional list of supported capabilities
    # @return [Remotes::Protocol] A new protocol connection instance
    def start_agent(name, program, url, capabilities = [])
      # Convert the program and URL into a properly formatted shell command
      argv = build_agent_command(program, url)
      
      # Open a bidirectional pipe to the agent process
      # input: Write to the process
      # output: Read from the process
      # _: stderr (ignored)
      input, output, _ = Open3.popen2(Shellwords.shelljoin(argv))

      # Establish a new protocol connection using the pipes
      @conn = Remotes::Protocol.new(name, output, input, capabilities)
    end

    # Constructs the shell command for launching the agent
    # @param program [String] The program/command to execute 
    # @param url [String] The URL to connect to
    # @return [Array] The command split into arguments
    def build_agent_command(program, url)
      # Parse the URL to extract its components
      uri = URI.parse(url)
      
      # Split the program into shell arguments and append the path component of the URL
      Shellwords.shellsplit(program) + [uri.path]
    end

    def report_ref_update(ref_names, error, old_oid = nil, new_oid = nil, is_ff=false)
      # First handle error cases - show rejection message if there's an error
      return show_ref_update("!", "[rejected]", ref_names, error) if error
      # Skip if old and new commits are identical (no change)
      return if old_oid == new_oid

      # Handle special cases:
      if old_oid == nil
        # New branch creation - no previous commit
        show_ref_update("*", "[new branch]", ref_names)
      elsif new_oid == nil
        # Branch deletion - no new commit
        show_ref_update("-", "[deleted]", ref_names)
      else
        # Normal update case - show range of commits changed
        report_range_update(ref_names, old_oid, new_oid, is_ff)
      end
    end

    def report_range_update(ref_names, old_oid, new_oid, is_ff)
      # Convert full commit IDs to shortened display format
      old_oid = repo.database.short_oid(old_oid)
      new_oid = repo.database.short_oid(new_oid)

      if is_ff
        # Fast-forward update - show direct commit range with ..
        revisions = "#{ old_oid }..#{ new_oid }"
        show_ref_update(" ", revisions, ref_names)
      else
        # Non-fast-forward update - show divergent range with ...
        revisions = "#{ old_oid }...#{ new_oid }"
        show_ref_update("+", revisions, ref_names, "forced update")
      end
    end

    def show_ref_update(flag, summary, ref_names, reason=nil)
      # Convert reference names to their short format for display
      names = ref_names.compact.map { |name| repo.refs.short_name(name) }

      # Build the status message with format: " flag summary source -> target"
      message = " #{ flag } #{ summary } #{ names.join(" -> ") }"
      # Add reason in parentheses if one was provided
      message.concat(" (#{ reason })") if reason

      # Output the formatted message to stderr
      @stderr.puts message
    end


  end
end