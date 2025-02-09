require "pathname"
require_relative "../repository"
require "colorize"
require_relative "../diff"  
require_relative "./shared/print_diff"


module Command 
  class Diff < Base

    include PrintDiff
    
    NULL_OID = "0" * 40
    NULL_PATH = "/dev/null"
    
    def run 
      repo.index.load
      @status = repo.status

      setup_pager

      if @options[:cached]
        diff_head_index
      elsif @args.size == 2
        diff_commits
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
      @options[:patch] = true
      define_print_diff_options
      @parser.on("--cached","--staged") { @options[:cached] = true} 

      @parser.on("-1", "--base") { @options[:stage] = 1}
      @parser.on("-2", "--ours") { @options[:stage] = 2}
      @parser.on("-3", "--theirs") { @options[:stage] = 3}

    end
  

    private 

    def diff_head_index
      return if !@options[:patch]

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

    def diff_index_workspace
      return if !@options[:patch]

      paths = @status.conflicts.keys + @status.workspace_changes.keys

      paths.sort.each do |path|
        if @status.conflicts.has_key?(path)
          print_conflict_diff(path)
        else 
          print_workspace_diff(path)
        end
      end
     
    end

    def print_conflict_diff(path)
      puts "* Unmerged path #{ path }"

      target = from_index(path, @options[:stage])
      return if !target

      print_diff(target, from_file(path))
    end

    def print_workspace_diff(path)
      if @status.workspace_changes[path] == :modified
        print_diff(from_index(path), from_file(path))
      elsif  @status.workspace_changes[path] == :deleted
        print_diff(from_index(path), from_nothing(path))
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

    # def from_index(path)
    #   entry = repo.index.entry_for_path(path)
    #   Target.new(path, entry.oid, entry.mode.to_s(8))
    # end

    def from_index(path, stage = 0)
      entry = repo.index.entry_for_path(path, stage)
      entry ? from_entry(path, entry) : nil
    end

    def from_file(path)
      blob = Database::Blob.new(repo.workspace.read_file(path))
      oid = repo.database.hash_object(blob)
      mode = Index::Entry.mode_for_stat(@status.stats[path])

      Target.new(path, oid, mode.to_s(8), blob.data)
    end

    def diff_commits
      return if !@options[:patch]
      a, b = @args.map { |rev| Revision.new(repo, rev).resolve }
      print_commit_diff(a, b)
    end
    
  end
end