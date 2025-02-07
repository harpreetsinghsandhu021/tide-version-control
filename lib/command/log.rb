require "colorize"

module Command
  class Log < Base
    
    def run 
      setup_pager
      each_commit { |commit| show_commit(commit) }
      
      exit 0
    end

    def each_commit
      oid = repo.refs.read_head

      while oid 
        commit = repo.database.load(oid)
        yield commit
        oid = commit.parent
      end
    end

    def blank_line
      puts "" if defined? @blank_line
      @blank_line = true
    end

    def show_commit(commit)
      case @options[:format]
      when "medium" then show_commit_medium(commit)
      when "oneline" then show_commit_oneline(commit)
      end
    end

    def show_commit_medium(commit)
      author = commit.author

      blank_line
      puts "commit #{ abbrev(commit).colorize(:yellow) }"
      puts "Author: #{ author.name } <#{ author.email }>"
      puts "Date:   #{ author.readable_time }"
      blank_line

      commit.message.each_line { |line| puts "   #{ line }"}
    end

    def show_commit_oneline(commit)
      puts "#{ abbrev(commit).colorize(:yellow) } #{ commit.title_line }"
    end

    def define_options
      @options[:abbrev] = :auto
      
      @options[:format] = "medium"

      @parser.on "--pretty=<format>", "--format=<format>" do |format|
        @options[:format] = format
      end

      @parser.on "--oneline" do 
        @options[:abbrev] = true if @options[:abbrev] == :auto
        @options[:format] = "oneline"
      end

    end

    def abbrev(commit)
      if @options[:abbrev] == true
        repo.database.short_oid(commit.oid)
      else 
        commit.oid
      end
    end

  end
end