require "pathname"

class PathFilter
  # Designed for effeciently checking whether paths match a predefined set of allowed paths. It leverages 
  # a Trie internally to optimize the lookup process.


  # Implementation of trie data structure optimized for storing paths. Each node in the Trie represents a directory
  # or file segment, and the `matched` flag indicates whether the path segment has a complete allowed path.
  Trie = Struct.new(:matched, :children) do 
     # Constructs a Trie from an array of paths
    # For example if paths = ["/a/b/c", "/a/d"], then the Trie structure will be
    #  Trie(matched=true, children={
    #           "a" => Trie(matched=false, children={
    #               "b" => Trie(matched=false, children={
    #                 "c" => Trie(matched=true, children={})
    #                   }),
    #               "d" => Trie(matched=true, children={})
    #           })
    #       })
    def self.from_paths(paths)
      root = Trie.node # create a root node
      root.matched = true if paths.empty? # if paths is empty set root.matched to true

      paths.each do |path|
        trie = root # start from root of each path
        path.each_filename { |name| trie = trie.children[name] } # for each name in path create a new node if not present already
        trie.matched = true # set the last node`s match to true
      end

      root
    end

    def self.node
      Trie.new(false, Hash.new { |hash, key| hash[key] = Trie.node })
    end
  end
  
  def self.build(paths)
    PathFilter.new(Trie.from_paths(paths))
  end

  attr_reader :path
  
  def initialize(routes=Trie.new(true), path = Pathname.new(""))
    @routes = routes
    @path = path
  end

  # Iterates over a hash, yielding only those entries that match the trie stored in the routes variables.
  # i.e either the current trie`s matched flag is set, or it contains a child whose name matches the current entry.
  def each_entry(entries)
    entries.each do |name, entry|
      yield name, entry if @routes.matched || @routes.children_has_key?(name)
    end
  end


  # Navigate down the True based on directory/fine name.
  # @param name [String] The name of the directory or file to navigate to
  # @return [PathFilter] A new PathFilter instance representing the position in the Trie after traversing down the given name.
  def join(name)
    # If the current Trie mode is marked as "matched" (meaning it represents a complete path), then we start from the root of the 
    # Trie for the next level, otherwise we get the child node corresponding to the given name.
    next_routes = @routes.matched ? @routes : @routes.children[name]
    # a new PathFilter instance with the updated routes and the path extended with the given name.
    PathFilter.new(next_routes, @path.join(name))
  end
  

end