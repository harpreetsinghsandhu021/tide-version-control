require "colorize"

require_relative "../revision"
require_relative './shared/fast_forward'


module Command 
  class Branch < Base
    
    include FastForward

    def run 
      if @options[:upstream]
        set_upstream_branch
      elsif @options[:delete]
        delete_branches
      elsif @args.empty?
        list_branches
      else 
        create_branch
      end


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
      set_upstream(branch_name, start_point) if @options[:track]

    rescue Revision::InvalidObject => error
      revision.errors.each do |err|
        @stderr.puts "error: #{ err.message }"
        err.hint.each { |line| @stderr.puts "hint: #{ line }"}
      end
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end

    def define_options
      @parser.on "-u <upstream>", "--set-upstream-to=<upstream>" do |upstream|
        @options[:upstream] = upstream
      end

      @parser.on("-t", "--track") { @options[:track] = true }
      @parser.on("--unset-upstream") { @options[:upstream] = :unset}

      @parser.on("-a", "--all") { @options[:all] = true }
      @parser.on("-r", "--remotes") { @options[:remotes] = true }

      @options[:verbose] = 0
      @parser.on("-v", "--verbose") { @options[:verbose] += 1 }

      @parser.on("-d", "--delete") {@options[:delete] = true}
      @parser.on("-f", "--force") {@options[:force] = true}
      @parser.on "-D" do 
        @options[:delete] = @options[:force] = true
      end
    end

    def list_branches
      current = repo.refs.current_ref
      branches = branch_refs.sort_by(&:path)
      max_width = branches.map { |b| b.short_name.size }.max

      setup_pager

      branches.each do |ref|
        info = format_ref(ref, current)
        info.concat(extended_branch_info(ref, max_width))
        puts info
      end

    end

    def branch_refs
      branches = repo.refs.list_branches
      remotes = repo.refs.list_remotes
      return branches + remotes if @options[:all]
      return remotes if @options[:remotes]

      branches
    end

    def format_ref(ref, current)
      if ref == current
        "* #{ ref.short_name.colorize(:green) }"
      elsif ref.remote?
        " #{ ref.short_name.colorize(:red) }"
      else 
        " #{ ref.short_name }"
      end
    end

    def extended_branch_info(ref, max_width)
      return "" unless @options[:verbose] > 0

      commit = repo.database.load(ref.read_oid)
      short = repo.database.short_oid(commit.oid)
      space = " " * (max_width - ref.short_name.size)
      upstream = upstream_info(ref)

      "#{ space } #{ short }#{ upstream } #{ commit.title_line }"
    end

    def upstream_info(ref)
      divergence = repo.divergence(ref)
      return "" if !divergence.upstream

      ahead = divergence.ahead
      behind = divergence.behind
      info = []

      if @options[:verbose] > 1
        info.push(fmt(:blue, repo.refs.short_name(divergence.upstream)))
      end

      info.push("ahead #{ ahead }") if ahead > 0
      info.push("behind #{ behind }") if behind > 0

      info.empty? ? "" : " [#{ info.join(", ")}]"
    end

    def delete_branches
      @args.each { |branch_name| delete_branch(branch_name) }
    end
    
    def delete_branch(branch_name)
      check_merge_status if !@options[:force]

      oid = repo.refs.delete_branch(branch_name)
      short = repo.database.short_oid(oid)

      puts "Deleted branch #{ branch_name } (was #{ short })."

    rescue Refs::InvalidBranch => error
      @stderr.puts "error: #{ error }"
      exit 1
    end

    def set_upstream_branch
      branch_name = @args.first || repo.refs.current_ref.short_name

      if @options[:upstream] == :unset
        repo.remotes.unset_upstream(branch_name)
      else 
        set_upstream(branch_name, @options[:upstream])
      end
    end

    def set_upstream(branch_name, upstream)
      upstream = repo.refs.long_name(upstream)
      remote, ref = repo.remotes.set_upstream(branch_name, upstream)

      base = repo.refs.short_name(ref)

      puts "Branch '#{ branch_name }' set up to track remote " + "branch '#{ base }' from '#{ remote }'"

    rescue Refs::InvalidBranch => error
      @stderr.puts "error: #{ error.message }"
      exit 1

    rescue Remotes::InvalidBranch => error
      @stderr.puts "fatal: #{ error.message }"
      exit 128
    end

    def check_merge_status(branch_name)
      upstream = repo.remotes.get_upstream(branch_name)
      head_oid = upstream ? repo.refs.read_ref(upstream) : repo.refs.read_head
      branch_oid = repo.refs.read_ref(branch_name)

      if fast_forward_error(branch_oid, head_oid)
        @stderr.puts "error: The branch '#{ branch_name }' is not fully merged."
        exit 1
      end
    end

  end
end