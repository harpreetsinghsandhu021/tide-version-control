
class Database
  class TreeDiff
    
    attr_reader :changes 

    def initialize(database)
      @database = database
      @changes = {}
    end

    # Compares two Trees
    # @param a [String] OID of the first tree object
    # @param b [String] OID of the second tree object
    # @param prefix [Pathname] will be used to construct the full path to each changed file as we recurse down trees
    def compare_oids(a, b, filter)
      return if a == b

      a_entries = a ? oid_to_tree(a).entries : {}
      b_entries = b ? oid_to_tree(b).entries : {}

      detect_deletions(a_entries, b_entries, filter)
      detect_additions(a_entries, b_entries, filter)
    end

    def oid_to_tree(oid)
      object = @database.load(oid)

      case object
      when Commit then @database.load(object.tree)
      when Tree then object
      end
    end

    # Detect changes between the two trees
    def detect_deletions(a, b, filter)
      filter.each_entry(a) do |name, entry|
        other = b[name]

        next if entry == other # If entries are equal, skip to the next entry

        sub_filter = filter.join(name)

        tree_a, tree_b = [entry, other].map { |e| e&.tree? ? e.oid : nil}
        compare_oids(tree_a, tree_b, sub_filter)

        blobs = [entry, other].map { |e| e&.tree? ? nil : e }
        @changes[sub_filter.path] = blobs if blobs.any?
      end
    end

    # Detect entries that exist in the second tree but not in first
    def detect_additions(a, b, filter)
      filter.each_entry(b) do |name, entry|
        other = a[name]

        next if other # skipping any entries that exist in a

        sub_filter = filter.join(name)

        if entry.tree?
          compare_oids(nil, entry.oid, sub_filter)
        else
            @changes[sub_filter.path] = [nil, entry]
        end
      end
    end

  end
end