require "pathname"
require_relative "../repository"
require "colorize"
require_relative "../diff"  
require_relative "./shared/print_diff"

# Command module containing git command implementations
module Command 
  # Diff class handles the tide diff command functionality
  # Compares changes between working directory, index, and commits
  class Diff < Base

    include PrintDiff
    
    # Constant representing empty git object (40 zeros)
    NULL_OID = "0" * 40
    # Constant representing null file path
    NULL_PATH = "/dev/null"
  
    def run 
      # Load the index to ensure we have latest state
      repo.index.load
      @status = repo.status

      setup_pager

      if @options[:cached]
        # Compare HEAD with index
        diff_head_index
      elsif @args.size == 2
        # Compare two commits
        diff_commits
      else 
        # Compare index with workspace
        diff_index_workspace
      end

      exit 0
    end

    # Target struct represents a file state at a specific point
    # Used to compare different versions of files
    Target = Struct.new(:path, :oid, :mode, :data) do 
      def diff_path 
        mode ? path : NULL_PATH
      end
    end

    # Define command line options for diff command
    def define_options
      @options[:patch] = true
      define_print_diff_options
      # --cached or --staged shows diff between HEAD and index
      @parser.on("--cached","--staged") { @options[:cached] = true} 

      # Options for handling merge conflicts
      @parser.on("-1", "--base") { @options[:stage] = 1}
      @parser.on("-2", "--ours") { @options[:stage] = 2}
      @parser.on("-3", "--theirs") { @options[:stage] = 3}
    end
  
    private 

    # Compare changes between HEAD and index
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

    # Get file state from HEAD commit
    def from_head(path)
      entry = @status.head_tree.fetch(path)
      from_entry(path, entry)
    end

    # Compare changes between index and workspace
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

    # Print diff for files with merge conflicts
    def print_conflict_diff(path)
      targets = (0..3).map { |stage| from_index(path, stage) }
      left, right = targets[2], targets[3]

      if @optionsp[:stage]
        puts "* Unmerged path #{ path }"
        print_diff(targets[@options[:stage]], from_file(path))
      elsif left and right
        print_combined_diff([left, right], from_file(path))
      else 
        puts "* Unmerged path #{ path }"
      end
    end

    # Print combined diff for merge conflicts
    def print_combined_diff(as, b)
      header("diff --c #{ b.path }")

      a_oids = as.map { |a| short a.oid }
      oid_range = "index #{ a_oids.join(",") }..#{ short b.oid }"
      header(oid_range)

      if !as.all? { |a| a.mode == b.mode}
        header("mode #{ as.map(&:mode).join(",") }..#{ b.mode }")
      end

      header("--- a/#{ b.diff_path }")
      header("+++ b/#{ b.diff_path }")

      hunks = ::Diff.combined_hunks(as.map(&:data), b.data)
      hunks.each { |hunk| print_diff_hunk(hunk) } 
    end

    # Print diff for workspace changes
    def print_workspace_diff(path)
      if @status.workspace_changes[path] == :modified
        print_diff(from_index(path), from_file(path))
      elsif  @status.workspace_changes[path] == :deleted
        print_diff(from_index(path), from_nothing(path))
      end
    end

    # Handle modified file diff
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

    # Handle deleted file diff
    def diff_file_deleted(path)
      entry = repo.index.entry_for_path(path)

      a_oid = entry.oid
      a_mode

      a = Target.new(path, a_oid, a_mode.to_s(8))
      b = Target.new(path, NULL_OID, nil)

      print_diff(a, b)
    end

    # Get file state from index for given path and stage
    def from_index(path, stage = 0)
      entry = repo.index.entry_for_path(path, stage)
      entry ? from_entry(path, entry) : nil
    end

    # Get file state from working directory
    def from_file(path)
      blob = Database::Blob.new(repo.workspace.read_file(path))
      oid = repo.database.hash_object(blob)
      mode = Index::Entry.mode_for_stat(@status.stats[path])

      Target.new(path, oid, mode.to_s(8), blob.data)
    end

    # Compare two commits
    def diff_commits
      return if !@options[:patch]
      a, b = @args.map { |rev| Revision.new(repo, rev).resolve }
      print_commit_diff(a, b)
    end
    
  end
end