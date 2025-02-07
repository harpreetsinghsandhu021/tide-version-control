require "colorize"

module Command
  class Log < Base

    include PrintDiff
    
    def run 
      setup_pager

      @reverse_refs = repo.refs.reverse_refs
      @current_ref = repo.refs.current_ref

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
      return if @options[:format] == "oneline"
      puts "" if defined? @blank_line
      @blank_line = true
    end

    def show_commit(commit)
      case @options[:format]
      when "medium" then show_commit_medium(commit)
      when "oneline" then show_commit_oneline(commit)
      end

      show_patch(commit)
    end

    def show_commit_medium(commit)
      author = commit.author
    
      blank_line
      puts "commit #{ abbrev(commit).colorize(:yellow) + decorate(commit) }"
      puts "Author: #{ author.name } <#{ author.email }>"
      puts "Date:   #{ author.readable_time }"
      blank_line

      commit.message.each_line { |line| puts "   #{ line }"}
    end

    def show_commit_oneline(commit)
      puts "#{ abbrev(commit).colorize(:yellow) + decorate(commit) } #{ commit.title_line }"
    end

    def define_options
      @options[:patch] = false
      define_print_diff_options
      @options[:abbrev] = :auto
      
      @options[:format] = "medium"

      @parser.on "--pretty=<format>", "--format=<format>" do |format|
        @options[:format] = format
      end

      @parser.on "--oneline" do 
        @options[:abbrev] = true if @options[:abbrev] == :auto
        @options[:format] = "oneline"
      end

      @options[:decorate] = "auto"

      @parser.on "--decorate[=<format>]" do |format|
        @options[:decorate] = format || "short"
      end

      @parser.on "--no-decorate" do 
        @options[:decorate] = "no"
      end

    end

    def abbrev(commit)
      if @options[:abbrev] == true
        repo.database.short_oid(commit.oid)
      else 
        commit.oid
      end
    end

    def decorate(commit)
      case @options[:decorate]
      when "auto" then return "" if !@isatty
      when "no" then return ""
      end

      refs = @reverse_refs[commit.oid]
      return "" if refs.empty?

      head, refs = refs.partition { |ref| ref.head? and not @current_ref.head? }
      names = refs.map { |ref| decoration_name(head.first, ref) }

      " (".colorize(:yellow) + names.join(", ".colorize(:yellow)) + ")".colorize(:yellow)
    end

    def decoration_name(head, ref)
      case @options[:decorate]
      when "short", "auto" then name = ref.short_name
      when "full" then name = ref.path
      end

      name = name.colorize(ref_color(ref)).bold
      if head and ref == @current_ref
        name = "#{ head.path } -> #{ name }".colorize(ref_color(head)).bold
      end

      name
    end

    def ref_color(ref)
      ref.head? ? :cyan : :green
    end

    def show_patch(commit)
      return if !@options[:patch]

      blank_line
      print_commit_diff(commit.parent, commit.oid)
    end

  end
end