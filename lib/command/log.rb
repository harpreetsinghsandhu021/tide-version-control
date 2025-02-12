require "colorize"
require_relative "./shared/print_diff"
require_relative "../rev_list"

module Command
  class Log < Base

    include PrintDiff
    
    def run 
      setup_pager

      @reverse_refs = repo.refs.reverse_refs
      @current_ref = repo.refs.current_ref

      @rev_list = RevList.new(repo, @args)
      @rev_list.each { |commit| show_commit(commit) }
      
      exit 0         
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
      if commit.merge?
        oids = commit.parents.map { |oid| repo.database.short_oid(oid) }
        puts "Merge: #{ oids.join(" ") }"
      end
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

      @parser.on "--c" do
        @options[:combined] = @options[:patch] = true
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
      return if !@options[:patch] and commit.parents.size <= 1
      return show_merge_patch(commit) if commit.merge?

      blank_line
      print_commit_diff(commit.parent, commit.oid, @rev_list)
    end

    def show_merge_patch(commit)
      return if @options[:combined]

       # 1. It looks at the commit's parents (remember, merges have two!)
       # 2. For each parent, it calculates the difference in files (a "tree diff") 
       # between that parent and the current commit.
       # 3. All these diffs are stored in a list called 'diffs'.
      diffs = commit.parents.map { |oid| @rev_list.tree_diff(oid, commit.oid) }

      # Now, we want to find files that were changed in BOTH parent branches.
      # 1. We look at the first diff and get a list of all the file paths it touched.
      # 2. We check if ALL the other diffs also have those paths.
      paths = diffs.first.keys.select do |path|
        diffs.drop(1).all? { |diff| diff.has_key?(path) }
      end

      blank_line

      # For each file that was changed in both branches.
      paths.each do |path|
        # Get the target from both parents.
        parents = diffs.map { |diff| from_entry(path, diff[path][0]) }
        # get the target from the merged commit.
        child = from_entry(path, diffs.first[path][1])

        # Show how merge resolved the changes.
        print_combined_diff(parents, child)
      end
    end

  end
end