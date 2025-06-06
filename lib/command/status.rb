require_relative './base'
require "set"
require "sorted_set"
require "colorize"
require_relative "../sorted_hash"

module Command
  # Implements the 'tide status' command
  # Shows the working tree status, including modified and untracked files
  class Status < Base

    # Main execution method for the status command
    # Scans workspace and shows modified/untracked files
    # @return [void]
    
    SHORT_STATUS = {
      :added => "A", 
      :deleted => "D", 
      :modified => "M", 
    }

    LABEL_WIDTH = 12

    LONG_STATUS = {
      :added => "new file:", 
      :deleted => "deleted:", 
      :modified => "modified:"
    }

    CONFLICT_LABEL_WIDTH = 17

    CONFLICT_LONG_STATUS = {
      [1, 2, 3] => "both modified:", 
      [1, 2] => "deleted by them:", 
      [1, 3] => "deleted by us:", 
      [2, 3] => "both added:", 
      [2] => "added by us:", 
      [3] => "added by them:"
    }

    CONFLICT_SHORT_STATUS = {
      [1, 2, 3] => "UU", 
      [1, 2] => "UD", 
      [1, 3] => "DU", 
      [2, 3] => "AA", 
      [2] => "AU", 
      [3] => "UA:"
    }

    UI_LABELS = { :normal => LONG_STATUS, :conflict => CONFLICT_LONG_STATUS }
    UI_WIDTHS = { :normal => LABEL_WIDTH, :conflict => CONFLICT_LABEL_WIDTH}

    def run

      repo.index.load_for_update
      @status = repo.status
      repo.index.write_updates

      print_results

      exit 0
    end

    # Prints the Status of Files
    def print_results
      if @options[:format] == "porcelain"
        print_porcelain_format
      else
        print_long_format 
      end
    end

    def print_porcelain_format
      @status.changed.each do |path|
        status = status_for(path)
        puts "#{ status } #{ path }"
      end

      return if @status.untracked_files.nil?
      @status.untracked_files.each do |path|
        puts "?? #{ path }"
      end
    end

    def print_long_format
      print_branch_status
      print_upstream_status
      print_pending_commit_status

      print_changes("Changes to be committed", @status.index_changes, :green)
      print_changes("Unmerged paths", @status.conflicts, :red, :conflict)
      print_changes("Changes not staged for commit", @status.workspace_changes, :red)
      print_changes("Untracked files", @status.untracked_files, :red)

      print_commit_status
    end

    def print_branch_status
      current = repo.refs.current_ref

      if current.head?
        puts "Not currently on any branch".colorize(:red)
      else 
        puts "On branch #{ current.short_name }"
      end
    end

    def print_upstream_status
      divergence = repo.divergence(repo.refs.current_ref)
      return if !divergence.upstream

      base = repo.refs.short_name(divergence.upstream)
      ahead = divergence.ahead
      behind = divergence.behind

      if ahead == 0 && behind == 0
        puts "Your branch is up to date with '#{ base }'."
      elsif behind == 0
        puts "Your branch is ahead of '#{ base }' by #{ commits ahead }"
      elsif ahead == 0
        puts "Your branch is behind '#{ base }' by #{ commits behind }, and can be fast-forwarded." 
      else 
        puts <<~MSG
          Your branch and '#{ base }' have diverged, 
          and have #{ ahead } and #{ behind } different commits each, respectively. 
        MSG
      end

      puts ""
    end

    def commits(n)
      n == 1 ? "1 commit" : "#{ n } commits"
    end


    def print_changes(message, changeSet, style, label_set = :normal)
      return if changeSet.nil? || changeSet.empty?

      labels = UI_LABELS[label_set]
      width = UI_WIDTHS[label_set]

      puts "#{message}:"
      puts ""

      changeSet.each do |path, type|
        status = type ? labels[type].ljust(width, " ") : ""
        puts "\t#{ status }#{ path }".colorize(style)
      end
      puts ""
    end

    def print_commit_status
      return if @status.index_changes.any?

      if @status.workspace_changes.any?
        puts "no changes added to commit (use 'tide add' and/or 'tide commit -a')"
      elsif @status.untracked_files.any?
        puts "nothing added to commit but untracked files present"
      else 
        puts "nothing to commit, working tree clean"
      end

    end

    # Determines the status of a file
    # returns statuses for HEAD/index changes as well as index/workspace
    # differences
    def status_for(path)
      if @status.conflicts.has_key?(path)
        CONFLICT_SHORT_STATUS[@status.conflicts[path]]
      else
        left = SHORT_STATUS.fetch(@status.index_changes[path], " ")
        right = SHORT_STATUS.fetch(@status.workspace_changes[path], " ")
        
        left + right
      end
    end

    def define_options
      @options[:format] = "long"
      @parser.on("--porcelain") { @options[:format] = "porcelain"}
    end

    def print_pending_commit_status
      case repo.pending_commit.merge_type
      when :merge
        if @status.conflicts.empty?
          puts "All conflicts fixed but you are still merging."
          hint "use 'tide commit' to conclude merge"
        else 
          puts "You have unmerged paths."
          hint "fix conflicts and run 'tide commit'"
          hint "use 'tide merge --abort' to abort the merge"
        end
        puts ""

      when :cherry_pick
        print_pending_type(:cherry_pick)
      when :revert
        print_pending_type(:revert)
      end
    end

    def print_pending_type(merge_type)
      oid = repo.pending_commit.merge_oid(merge_type)
      short = repo.database.short_date(oid)
      op = merge_type.to_s.sub("_","-")

      puts "You are currently #{ op }ing commit #{ short }"

      if @status.conflicts.empty?
        hint "all conflicts fixed: run 'tide #{ op } --continue'"
      else 
        hint "fix conflicts and run 'tide #{ op } --continue'"
      end

      hint "use 'tide #{ op } --abort' to cancel the #{ op } operation"
      puts ""
    end
  

    def hint(message)
      puts "  (#{ message })"
    end

  end
end
