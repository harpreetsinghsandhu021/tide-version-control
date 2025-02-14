require_relative "./revision"
require_relative "./path_filter"

class RevList
  # RevList is responsible for traversing commit history and filtering commits based on various criteria.
  # It implements Git's revision walking algorithm, which is used in commands like `git log`.
  #
  # Key features:
  # - Traverses commit history in reverse chronological order
  # - Supports revision range expressions (e.g., "master..feature")
  # - Handles commit exclusions (e.g., "^commit-id")
  # - Supports path filtering to show only commits that modify specific files
  # - Implements history simplification to skip commits that don't change tracked paths


  include Enumerable

  RANGE = /^(.*)\.\.(.*)$/
  EXCLUDE = /^\^(.+)$/

  def initialize(repo, revs, options = {})
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

    @walk = options.fetch(:walk, true)

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

      @walk = true
    elsif match = EXCLUDE.match(rev)
      set_start_point(match[1], false)
      @walk = true
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

  # Marks all ancestors of a given commit as uninteresting.
  # This is used to exclude certain commits from being considered as merge bases.
  # @param commit [Commit] The commit whose ancestors should be marked as uninteresting.
  def mark_parents_uninteresting(commit)
   queue = commit.parents.clone

   until queue.empty?
     oid = queue.shift
     next if !mark(oid, :uninteresting)
     commit = @commits[oid]
     # Add the parents of the current commit to the queue.
     # This ensures that all ancestors of the original commit are processed.
     queue.concat(commit.parents) if commit
   end
  end

  # Takes the Commit object, and marks it with the :seen flag if not set before, this means the commit has already been 
  # visited and we don`t need to reprocess it.
  def enqueue_commit(commit)
    return if !mark(commit.oid, :seen)

    # Finds the first item in the queue whose date is earlier than the new commit
    # and inserts the commit before that item, or at the end of the queue if no such item was found.
    # This keeps the queue ordered in reverse date order
    
    if @walk
      index = @queue.find_index { |c| c.date < commit.date }
      @queue.insert(index || @queue.size, commit)
    else
      @queue.push(commit)
    end
    
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


  # Adds the parents of a given commit to the processing queue
  # prevents re-processing of the same commit and handles marking parents as uninteresting if needed
  def add_parents(commit)
    # check the mark to see if its added before to prevent reprocessing.
    # check the @walk to prevent RevList iterating over all the commits reachable from the inputs
    # and will yield only the inputs themselves.
    return if !@walk && !mark(commit.oid, :added) 

    if marked?(commit.oid, :uninteresting)
      parents = commit.parents.map { |oid| load_commit(oid) }
      parents.each {|parent| mark_parents_uninteresting(parent) }
    else 
      parents = simplify_commit(commit).map { |oid| load_commit(oid) }
    end

    parents.each { |parent| enqueue_commit(parent) }
  end

  # Simplifies the commit history by identifying commits that don't introduce changes
  # to the paths being considered (as specified by the `@prune` set). 
  # @param commit [Commit] The commit to be analyzed for simplification.
  # @return [Array<String>, nil] An array of parent OIDs to follow if the commit is 
  # simplified, otherwise returns the original commit's parents.
  def simplify_commit(commit)
    return commit.parents if @prune.empty? # If no paths are being filtered, no simplification is needed
    
    parents = commit.parents 
    parents = [nil] if parents.empty?

    parents.each do |oid|
      # If the tree diff is not empty (meaning there are changes), move to the next parent.
      next if !tree_diff(oid, commit.oid).empty? 

      # If the tree diff is empty, it means the commit doesn't introduce changes 
      # to the paths we care about.
      # Mark the commit as having the same tree as its parent.
      mark(commit.oid, :treesame) 

      # Return an array containing only the current parent's OID. 
      # This effectively simplifies the history by making the current commit
      # seemingly directly follow this parent.
      return [*oid]
    end

    # If none of the parents resulted in simplification,
    # return the original list of the commit's parents.
    commit.parents 
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