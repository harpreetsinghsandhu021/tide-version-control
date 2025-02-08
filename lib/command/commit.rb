require "pathname"
require_relative '../repository'
require_relative '../database/tree'
require_relative '../database/author'
require_relative '../database/commit'

require_relative "./shared/write_commit"

module Command 
  class Commit < Base

    include WriteCommit
    
    def run  
      repo.index.load
      root = Database::Tree.build(repo.index.each_entry)
      root.traverse { |tree| repo.database.store(tree) }

      parent = repo.refs.read_head()
      message= @stdin.read

      commit = write_commit([*parent], message)

      is_root = parent.nil? ? "(root-commit)" : ""
      puts "[#{ is_root }#{ commit.oid }] #{ message.lines.first }"
      exit 0
    end
  end
end