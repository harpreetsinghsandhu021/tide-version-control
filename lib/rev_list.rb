require_relative "./revision"
require_relative "./path_filter"

class RevList 

  RANGE = /^(.*)\.\.(.*)$/
  EXCLUDE = /^\^(.+)$/

  def initialize(repo, revs)
    @repo = repo

    # Caches every commit that we load.
    # It will initially prevent re-loading data we already have.
    # It will help us locate commits we`ve loaded whose information needs to be updated.
    @commits = {} 

    # As we walk through the history graph, we`ll associate various flags to mark 
    # their status i.e visited commit.
    @flags = Hash.new { |hash, oid| hash[oid] = Set.new }

    # Stores the commit-time priority queue of commits we still need to visit.
    @queue = []

    # RevList is limited if it has any excluded start points.
    @limited = false

    # Stores a list of buffers of possible output commits that`s distinct from the input queue.
    @output = []

    # Stores a list of file paths that should be excluded from the revision traversal.
    @prune = []

    # Caches the treediffs we calculate.
    @diffs = {}

    @filter = PathFilter.build(@prune)

    revs.each { |rev| handle_revision(rev) }

    handle_revision(Revision::HEAD) if @queue.empty?
  end

  # def each 
  #   oid = Revision.new(@repo, @start). resolve(Revision::COMMIT)

  #   while oid 
  #     commit = @repo.database.load(oid)
  #     yield commit
  #     oid = commit.parent
  #   end
  # end

  # Adds a flag to a given commit ID using Set.add which returns true only if the 
  # flag was not already in the commit`s set
  def mark(oid, flag)
    @flags[oid].add?(flag)
  end

  # Uses Set.include to check whether a commit has a certain flag without changing its state
  def marked?(oid, flag)
    @flags[oid].include?(flag)
  end

  # Processes a single revision expression and updates the internal state of the RevList 
  # accordingly
  # @param rev [String] The revision expression to handle
  def handle_revision(rev)
    if @repo.workspace.stat_file(rev) # check if the revision is a file path existing in the workspace
      @prune.push(Pathname.new(rev))
    elsif match = RANGE.match(rev)
      set_start_point(match[1], false)
      set_start_point(match[2], true)
    elsif match = EXCLUDE.match(rev)
      set_start_point(match[1], false)
    else 
      set_start_point(rev, true)
    end
  end

  # Adds a starting commit to the revision traversal
  # @param rev [String] The revision expression (e.g., "HEAD", "master~2").
  # @param interesting [Boolean] Whether the commit is interesting for output.
  def set_start_point(rev, interesting)
    rev = Revision::HEAD if rev == "" # Default to HEAD if the revision is empty
    oid = Revision.new(@repo, rev).resolve(Revision::COMMIT) # resolve the revision expression to a commit ID

    commit = load_commit(oid) # Load commit object from the database
    enqueue_commit(commit) # enqueue the commit for traversal

    # If the commit is not interesting:
    if !interesting
      @limited = true # mark the revision list as limited (containing exclusions)
      mark(oid, :uninteresting) # mark the commit as uninteresting to exclude it from output
      mark_parents_uninteresting(commit) 
    end
  end

  # Recursively mark all parent commits as uninteresting
  def mark_parents_uninteresting(commit)
    # Iterate over parent commits until there are no more parents or we encounter a parent
    # that`s already marked as unintersting
    while commit&.parent
      break if !mark(commit.parent, :uninteresting)

      # Load the parent commit from the cache
      commit = @commits[commit.parent]
    end
  end

  # Takes the Commit object, and marks it with the :seen flag if not set before, this means the commit has already been 
  # visited and we don`t need to reprocess it.
  def enqueue_commit(commit)
    return if !mark(commit.oid, :seen)

    # Finds the first item in the queue whose date is earlier than the new commit
    # and inserts the commit before that item, or at the end of the queue if no such item was found.
    # This keeps the queue ordered in reverse date order
    index = @queue.find_index { |c| c.date < commit.date }
    @queue.insert(index || @queue.size, commit)
  end

  # Walks the graph history, yielding all the commits in order
  def each 
    limit_list if @limited
    traverse_commits { |commit| yield commit }
  end

  # Limits the revision list based on uninteresting commits
  # Modifies the @queue to only contain commits that are 
  # reachable from the interesting commits while excluding the 
  # uninteresting commits and their ancestors
  def limit_list
    # Continue until there are no more potentially interesting commits
    while still_interesting?
      commit = @queue.first # Get the next most recent commit from the proiority queue
      add_parents(commit) # add the parent of this commit to the queue for further processing

      # If the curent commit is not marked as uninteresting, add it to the output list
      if !marked?(commit.oid, :uninteresting)
        @output.push(commit)
      end
    end    
    
    # Replace the queue with the filteres output list, which now contains only the interesting 
    # commits in reverse chronlogical order
    @queue = @output
  end

  # Checks if there are still potentially interesting commits to be processed in the queue
  # @return [Boolean] True if there are still interesting commits, false otherwise.
  def still_interesting?
    return false if @queue.empty? # If the queue is empty, there are no more commits to process

    oldest_out = @output.last
    newest_in = @queue.first

    # If the oldest commit in the output list is newer than the newest commit, we know all remaining commits in 
    # the queue are ancestors of an uninteresting commit and can be ignored
    return true if oldest_out and oldest_out.date <= newest_in.date

    # If any commit in the queue is not marked as uninteresting, then there are still interesting commits to process
    if @queue.any? { |commit| not marked?(commit,oid, :uninteresting) }
      return true
    end

    # otherwise, all remaining commits are uninteresting
    false
  end


  # Walks through the commit history, yielding each interesting commit. 
  # It processes commits from the @queue in reverse chronological order, adding parents of commits
  # for further exploration (unless exclusions are present). If the Revlist is limited, it will have already 
  # pruned the queue to only contain interesting commits, so add_parents won`t be called
  def traverse_commits
    until @queue.empty? 
      commit = @queue.shift
      add_parents(commit) if !@limited # Add its parents to the queue for processing (if not limited by exclusions)
      next if marked?(commit.oid, :uninteresting) # Skip if the commit is marked as uninteresting
      next if marked?(commit.oid, :treesame) # Skip if the commit tree is same as parent commit tree

      yield commit
    end
  end


  # Adds the parent of a given commit to the processing queue
  # prevents re-processing of the same commit and handles marking parents as uninteresting if needed
  def add_parents(commit)
    return if !mark(commit.oid, :added) # check the mark to see if its added before to prevent reprocessing

    parent = load_commit(commit.parent)
    return if !parent

    if marked?(commit.oid, :uninteresting)
      mark_parents_uninteresting(parent)
    else 
      simplify_commit(commit)
    end

    enqueue_commit(parent)
  end

  # Simplifies a commit by marking it as :treesame if it does`nt introduce changes to the filteres paths
  def simplify_commit(commit)
    return if @prune.empty? # If no paths are being filtered, no simplification is needed
    # mark the commit as :treesame if the treediff with its parent is empty
    mark(commit.oidm :treesame) if tree_diff(commit.parent, commit.oid).empty? 
  end

  def load_commit(oid)
    return nil if !oid
    @commits[oid] ||= @repo.database.load(oid)
  end

  def tree_diff(old_oid, new_oid)
    key = [old_oid, new_oid]
    @diff[key] ||= @repo.database.tree_diff(old_oid, new_oid, @filter)
  end

end