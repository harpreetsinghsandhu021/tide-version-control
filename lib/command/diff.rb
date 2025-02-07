require "pathname"
require_relative "../repository"
require "colorize"
require_relative "../diff"  


module Command 
  class Diff < Base

    NULL_OID = "0" * 40
    NULL_PATH = "/dev/null"
    
    def run 
      repo.index.load
      @status = repo.status

      setup_pager

      if @options[:cached]
        diff_head_index
      else 
        diff_index_workspace
      end

      exit 0
    end

    Target = Struct.new(:path, :oid, :mode, :data) do 
      def diff_path 
        mode ? path : NULL_PATH
      end
    end


    def define_options

      @parser.on("--cached","--staged") { @options[:cached] = true}
    end
  

    private 

    def diff_head_index
      @status.index_changes.each do |path, state|
        if state == :modified
          print_diff(from_head(path), from_index(path))
        elsif state == :added 
          print_diff(from_nothing(path), from_index(path))
        elsif state == :deleted
          print_diff(from_head(path), from_index(path))
        end
      end
    end

    def from_head(path)
      entry = @status.head_tree.fetch(path)
      from_entry(path, entry)
    end

 

    def from_entry(path, entry)
      blob = repo.database.load(entry.oid)
      Target.new(path, entry.oid, entry.mode.to_s(8), blob.data)
    end

    def diff_index_workspace
      @status.workspace_changes.each do |path, state|
        if state == :modified
          print_diff(from_index(path), from_file(path))
        elsif state == :deleted
          print_diff(from_index(path), from_nothing(path))
        else 
        end
      end
    end

    def diff_file_modified(path)
      entry = repo.index.entry_for_path(path)

      a_oid = entry.oid
      a_mode = entry.mode

      blob = Database::Blob.new(repo.workspace.read_file(path))
      b_oid = repo.database.hash_object(blob)
      b_mode = Index::Entry.mode_for_stat(@status.stats[path])


      a = Target.new(path, a_oid, a_mode.to_s(8))
      b = Target.new(path, b_oid, b_mode.to_s(8))

      print_diff(a, b)
    end

    def diff_file_deleted(path)
      entry = repo.index.entry_for_path(path)

      a_oid = entry.oid
      a_mode

      a = Target.new(path, a_oid, a_mode.to_s(8))
      b = Target.new(path, NULL_OID, nil)

      print_diff(a, b)
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

    def from_index(path)
      entry = repo.index.entry_for_path(path)
      Target.new(path, entry.oid, entry.mode.to_s(8))
    end

    def from_index(path)
      entry = repo.index.entry_for_path(path)
      from_entry(path, entry)
    end

    def from_file(path)
      blob = Database::Blob.new(repo.workspace.read_file(path))
      oid = repo.database.hash_object(blob)
      mode = Index::Entry.mode_for_stat(@status.stats[path])

      Target.new(path, oid, mode.to_s(8), blob.data)
    end

    def from_nothing(path)
      Target.new(path, NULL_OID, nil, "")
    end

    def short(oid)
      repo.database.short_oid(oid)
    end

  end
end