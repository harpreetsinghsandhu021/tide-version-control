module Merge 
  class CommonAncestors
    # Designed to find common ancestors bw two commits within a repository. It leverages a queue
    # to perform a BFS through the commit history.
    
    # A constant Set representing the flags for commits reachable from both starting commits
    BOTH_PARENTS = Set.new([:parent1, :parent2])
    
    def initialize(database, one, two)
      @database = database
      # Hash to store flags for each visited commit.
      @flags = Hash.new { |hash, new| hash[oid] = Set.new } 
      # store commits that need to be visited
      @queue = []
      
      # Add the first commit to the queue and mark it as parent1
      insert_by_date(@queue, @database.load(one))
      @flags[one].add(:parent1)

       # Add the second commit to the queue and mark it as parent2
      insert_by_date(@queue, @database.load(two))
      @flags[two].add(:parent2)
    end

    # Inserts a commit into a list sorted by date.
    # @param list [Array] The list of commits to insert into.
    # @param commit [Commit] The commit to insert.
    def insert_by_date(list, commit)
      # Find the index of the first commit in list that has a later date than the given commit. If no such commit is found. index will be nil.
      index = list.find_index { |c| c.date < commit.date }

      # Insert the commit before the found commit, or at the end of the list if no later commit was found.
      list.insert(index || list.size, commit)
    end


    # Finds the BCA of the two commits using a BFS approach through the commit history
    def find 
      until @queue.empty?
        commit = @queue.shift
        flags = @flags[commit.oid]

        return commit.oid if flags == BOTH_PARENTS # If the commit is reachable by both starting commits, we found a common ancestor

        add_parents(commit, flags) # Add the commit's parents to the queue for processing.
      end
    end

     # Adds the parents of the given commit to the queue for processing.
     # @param commit [Commit] The commit whose parents to add.
     # @param flags [Set] The flags associated with the commit.
    def add_parents(commit, flags)
      return if !commit.parent # If the commit has no parent, skip it (this is the initial commit).

      parent = @database.load(commit.parent)

      # If the parent already has all the flags that this commit has, skip it (already processed).
      return if @flags[parent.oid].superset?(flags)

      @flags[parent.oid].merge(flags) # Add the current commit's flags to the parent's flags.
      insert_by_date(@queue, parent) # Insert the parent into the queue, maintaining the date order.
    end

  end
end