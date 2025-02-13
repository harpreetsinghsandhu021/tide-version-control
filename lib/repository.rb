require_relative './database'
require_relative './index'
require_relative './refs'
require_relative './workspace'
require_relative "./repository/migration"
require_relative './repository/status'
require_relative "./repository/pending_commit"
require_relative "./repository/hard_reset"

class Repository
  def initialize(git_path)
    @git_path = git_path
  end

  def database 
    @database ||= Database.new(@git_path.join('objects'))
  end

  def index
    @index ||= Index.new(@git_path.join('index'))
  end

  def refs 
    @refs ||= Refs.new(@git_path)
  end

  def workspace
    @workspace ||= Workspace.new(@git_path.dirname)
  end

  def status(commit_oid=nil) 
    Status.new(self, commit_oid)
  end

  def migration(tree_diff)
    Migration.new(self, tree_diff)
  end

  def pending_commit
    PendingCommit.new(@git_path)
  end

  def hard_reset(oid)
    HardReset.new(self, oid).execute
  end
end