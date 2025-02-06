require_relative "../revision"

module Command 
  class Branch < Base
    
    def run 
      create_branch
      exit 0
    end

    def create_branch
      branch_name = @args[0]
      start_point = @args[1]

      if start_point
        revision = Revision.new(repo, start_point)
        start_oid = revision.resolve(Revision::COMMIT) # we only want to get commit IDs as the value of branch references
      else 
        start_oid = repo.refs.read_head
      end

      repo.refs.create_branch(branch_name, start_oid)
    rescue Revision::InvalidObject => error
      revision.errors.each do |err|
        @stderr.puts "error: #{ err.message }"
        err.hint.each { |line| @stderr.puts "hint: #{ line }"}
      end
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end
  end
end