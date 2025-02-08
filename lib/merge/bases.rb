
module Merge 
  class Bases 
    # Responsible for finding the base commits for a merge between two commits.
    
    def initialize(database, one, two)
      @database = database
      @common = CommonAncestors.new(@database, one, [two])
    end

    # Finds the base commits for a merge between two commits.
    # It first finds all common ancestors of the two commits using `CommonAncestors.find`.
    # If there is only one or zero common ancestors, it returns those commits directly.
    # Otherwise, it iterates through the common ancestors and filters out redundant ones. 
    # A redundant commit is a commit that is an ancestor of another common ancestor.
    # @return [Array<String>] An array of OIDs representing the base commits for the merge
    def find
      @commits = @common.find
      return @commits if @commits.size <= 1 

      @redundant = Set.new
      @commits.each { |commit|  filter_commit(commit) }
      @commits - @redundant.to_am
    end

    # Filters out redundant commits from the list of common ancestors.
    # A redundant commit is a commit that is an ancestor of another common ancestor.
    # @param commit [String] The OID of the commit to check for redundancy.
    def filter_commit(commit)
      return if @redundant.include?(commit) # If the commit is already marked as redundant, return.

      # Create a list of other common ancestor commits, excluding the current commit which are already marked as redundant.
      others = @commits - [commit, *redundant]

      # Initialize a new CommonAncestors object to find common ancestors between the current commit and the others.
      common = CommonAncestors.new(@database, commit, others)

      common.find # Find the common ancestors.

      # If the current commit is marked as reachable from the second commit (`parent2`) by the common ancestor finder,
      # it means it's an ancestor of another common ancestor and therefore redundant.
      @redundant.add(commit) if common.marked?(commit, :parent2)

      # Filter the `others` list to keep only those commits that are reachable from the first commit (`parent1`).
      # This is because any commit reachable from `parent1` but not `parent2` cannot be a common ancestor of the original two commits.
      others.select! { |oid| common.marked?(oid, :parent1)}
      @redundant.merge(others)
    end

  end
end