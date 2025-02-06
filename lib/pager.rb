
class Pager
  # Launch a pager program as a child process that 
  # runs in paralled with the current tide process.
  
  PAGER_CMD = 'less'
  PAGER_ENV = { "LESS" => "FRX", "LV" => "-c" }

  attr_reader :input

  # @param env [Hash] Enviroment variables
  # @param stdout Output stream
  # @param stderr Output error stream
  def initialize(env = {}, stdout = $stdout, stderr = $stderr)
    env = PAGER_ENV.merge(env) # creates an extended enviroment by merging the two enviroments
    cmd = env["GIT_PAGER"] || env["PAGER"] || PAGER_CMD # select the name of the pager program

    reader, writer = IO.pipe # create a channel for process to send data to child process

    options = { :in => reader, :out => stdout, :err => stderr}

    @pid = Process.spawn(env, cmd, options) # start the pager process, it runs async so it does`nt block until the pager program exits
    @input = writer

    reader.close
  end

  # Takes a PID and blocks until the corresponding process has finished
  def wait
    Process.waitpid(@pid) if @pid
    @pid = nil
  end

end