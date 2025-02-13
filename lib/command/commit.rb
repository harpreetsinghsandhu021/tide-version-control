require "pathname"
require_relative '../repository'
require_relative '../database/tree'
require_relative '../database/author'
require_relative '../database/commit'
require_relative "../editor"

require_relative "./shared/write_commit"

module Command 
  class Commit < Base

    include WriteCommit

    COMMIT_NOTES = <<~MSG
      Please enter the commit message for your changes. Lines starting 
      with "#" will be ignored, and an empty message aborts the commit. 
    MSG
    
    def run  
      repo.index.load
      resume_merge if pending_commit.in_progress?
      root = Database::Tree.build(repo.index.each_entry)
      root.traverse { |tree| repo.database.store(tree) }

      parent = repo.refs.read_head()
      message = compose_message(read_message || reused_message)

      commit = write_commit([*parent], message)

      
      print_commit(commit)
      exit 0
    end


    def define_options 
      define_write_commit_options

      @parser.on "-C <commit>", "--reuse-message=<commit>" do |commit|
        @options[:reuse] = commit
        @options[:edit] = false
      end

      @parser.on "-c <commit>", "--reedit-message=<commit>" do |commit|
        @options[:reuse] = commit
        @options[:edit] = true
      end
    end

    def compose_message(message)
      edit_file(commit_message_path) do |editor|
        editor.puts(message || "")
        editor.puts("")
        editor.note(COMMIT_NOTES)

        editor.close if @options[:edit]
      end
    end


    def edit_file(path)
      Editor.edit(path, editor_command) do |editor|
        yield editor
        editor.close if @isatty
      end
    end

    def editor_command
      @env["GIT_EDITOR"] || @env["VISUAL"] || @env["EDITOR"]
    end

    def reused_message
      return nil if !@options.has_key?(:reuse)

      revision = Revision.new(repo, @options[:reuse])
      commit = repo.database.load(revision.resolve)

      commit.message
    end

  end
end