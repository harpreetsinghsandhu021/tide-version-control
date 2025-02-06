require "set"
require "sorted_set"

# Extends Ruby`s standard Hash with sorted key tracking and iteration
class SortedHash < Hash
  def initialize
    super 
    @keys = SortedSet.new
  end

  def []=(key, value)
    @keys.add(key)
    super
  end

  def each 
    @keys.each { |key| yield [key, self[key]]}
  end

end

# sorted_hash = SortedHash.new
# sorted_hash[3] = "three"
# sorted_hash[1] = "one"
# sorted_hash[2] = "two"
# sorted_hash[0] = "zero"

# sorted_hash.each do |key, value|
#   puts "#{key}: #{value}"
# end  
# 
# Output:
# 0: zero
# 1: one
# 2: two
# 3: three