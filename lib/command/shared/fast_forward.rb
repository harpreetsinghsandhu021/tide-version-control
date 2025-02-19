require_relative "../../merge/common_ancestors"

module Command
  # FastForward module provides functionality to check if Git reference updates
  # can be performed as fast-forward operations
  
  module FastForward
    # Checks if a reference update would be a fast-forward operation
    # Returns an error message if update is not possible, nil if valid
    # @param old_oid [String] Current commit ID of the reference
    # @param new_oid [String] Target commit ID for the update
    # @return [String, nil] Error message or nil if fast-forward is possible
    def fast_forward_error(old_oid, new_oid)
      # No error if either commit ID is missing
      return nil if !old_oid || !new_oid

      # Error if old commit isn't in database
      return "fetch first" if !repo.database.has?(old_oid)
      # Error if new commit isn't a descendant of old commit
      return "non-fast forward" if !fast_forward?(old_oid, new_oid)
    end

    # Determines if new_oid is a descendant of old_oid
    # Uses common ancestor computation to check relationship
    # @param old_oid [String] Base commit ID
    # @param new_oid [String] Target commit ID
    # @return [Boolean] true if new_oid is descendant of old_oid
    def fast_forward?(old_oid, new_oid)
      # Create common ancestors finder for the two commits
      common = ::Merge::CommonAncestors.new(repo.database, old_oid, [new_oid])
      # Find all common ancestors
      common.find
      # Check if old_oid is marked as ancestor of new_oid
      common.marked?(old_oid, :parent2)
    end

  end
end