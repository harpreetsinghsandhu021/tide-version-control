require "open3"
require "shellwords"
require "uri"

require_relative "../../remotes/protocol"

module Command
  # RemoteClient module provides functionality for establishing and managing
  # connections with remote Git processes/agents
  module RemoteClient


    REF_LINE = /^([0-9a-f]+) (.*)$/
    ZERO_OID = "0" * 40

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

    # Reads the refs sent by the remote agent, storing them in a hash mapping ref names 
    # to commit IDs.
    def recv_references
      @remote_refs = {}

      @conn.recv_until(nil) do |line|
        oid, ref = REF_LINE.match(line).captures
        @remote_refs[ref] = oid.downcase if oid != ZERO_OID
      end
    end

  end
end