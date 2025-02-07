require "colorize"


module Command
  module PrintDiff
    
    NULL_OID = "0" * 40
    NULL_PATH = "/dev/null"

    Target = Struct.new(:path, :oid, :mode, :data) do 
      def diff_path 
        mode ? path : NULL_PATH
      end
    end

    def define_print_diff_options
      @parser.on("-p" ,"-u", "--patch") { @options[:patch] = true }
      @parser.on("-s", "--no-patch") { @options[:patch] = false }
    end

    private

    def from_entry(path, entry)
      blob = repo.database.load(entry.oid)
      Target.new(path, entry.oid, entry.mode.to_s(8), blob.data)
    end

    def from_nothing(path)
      Target.new(path, NULL_OID, nil, "")
    end

    def header
      a_offset = offsets_for(:a_line, a_start).join(",")
      b_offset = offsets_for(:b_line, b_start).join(",")

      "@@ -#{ a_offset } +#{ b_offset } @@"
    end

    def short(oid)
      repo.database.short_oid(oid)
    end

    def print_commit_diff(a, b)
      diff = repo.database.tree_diff(a, b)
      paths = diff.keys.sort_by(&:to_s)

      paths.each do |path|
        old_entry, new_entry = diff[path]
        print_diff(from_entry(path, old_entry), from_entry(path, new_entry))
      end
    end

    def from_entry(path, entry)
      return from_nothing(path) if !entry

      blob = repo.database.load(entry.oid)
      Target.new(path, entry.oid, entry.mode_to_s(8), blob.data)
    end

    def print_diff(a, b)
      return if a.oid == b.oid and a.mode == b.mode

      a.path = Pathname.new("a").join(a.path)
      b.path = Pathname.new("b").join(b.path)

      puts "diff --tide #{ a.path } #{ b.path }".bold
      print_diff_mode(a, b)
      print_diff_content(a, b)
    end 

    def print_diff_mode(a, b)
      if a.mode == nil
        puts "new file mode #{ b.mode }"
      elsif b.mode == nil 
        puts "deleted file mode #{ a.mode }"
      elsif a.mode != b.mode
          puts "old mode #{a.mode}"
          puts "new mode #{b.mode}"
      end 
    end


    def print_diff_content(a, b)
      return if a.oid == b.oid

      oid_range = "index #{ short a.oid }..#{ short b.oid }".bold
      oid_range.concat(" #{ a.mode.colorize(:green) }") if a.mode == b.mode

      puts oid_range
      puts "--- #{ a.diff_path }".bold
      puts "+++ #{ b.diff_path }".bold

      hunks = ::Diff.diff_hunks(a.data, b.data)
      hunks.each { |hunk| print_diff_hunk(hunk) }
    end

    def print_diff_hunk(hunk)
      puts hunk.header.colorize(:cyan)
      hunk.edits.each { |edit| print_diff_edit(edit)}
    end

    def print_diff_edit(edit)
      text = edit.to_s.rstrip

      if edit.type == :eql
        puts text
      elsif edit.type == :ins
        puts text.colorize(:green)
      elsif edit.type == :del
        puts text.colorize(:red)
      end
    end



  end
end