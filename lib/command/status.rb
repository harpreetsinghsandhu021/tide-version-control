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

    def run

      repo.index.load_for_update
      @status = repo.status
      repo.index.write_updates

      print_results

      exit 0
    end

    # Prints the Status of Files
    def print_results
      if @args.first == '--porcelain'
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
      print_changes("Changes to be committed", @status.index_changes, :green)
      print_changes("Changes not staged for commit", @status.workspace_changes, :red)
      print_changes("Untracked files", @status.untracked_files, :red)

      print_commit_status
    end

    def print_changes(message, changeSet, style)
      return if changeSet.nil? || changeSet.empty?

      puts "#{message}:"
      puts ""

      changeSet.each do |path, type|
        status = type ? LONG_STATUS[type].ljust(LABEL_WIDTH, " ") : ""
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
      left = SHORT_STATUS.fetch(@status.index_changes[path], " ")
      right = SHORT_STATUS.fetch(@status.workspace_changes[path], " ")

      left + right
    end
  
  end
end
