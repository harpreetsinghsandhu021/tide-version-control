
module Diff
  class Combined 
    include Enumerable
    
    # Represents a row in the combined diff.
    Row = Struct.new(:edits) do 
      def to_s 
        # Map the edits array to an array of symbols, where each symbol represents the type of the edit. 
        # If the edit type is not found in the SYMBOLS object, use a space character instead. 
        symbols = edits.map { |edit| SYMBOLS.fetch(edit&.type, " ")}

        del = edits.find { |edit| edit&.type == :del} # Find the first deletion edit in the edits array. 

        # If a deletion edit was found, use its `a_line` attribute for the line number.
        # othwerise, use b_line attr of the first edit in the edits array.
        line = del ? del.a_line : edits.first.b_line

        symbols.join("") + line.text
      end
    end

    # @param diffs [Array<Array<Edit>>] An array of diffs, where each diff is an array of `Edit` objects.
    def initialize(diffs)
      @diffs = diffs
    end

    # Iterate over the combined diff, yielding each row as a Row object.
    def each 
      # Initialize an array of offsets, one for each diff.
      @offsets = @diffs.map { 0 } 

      loop do 
        # Iterate over each diff along with its index.
        @diffs.each_with_index do |diff, i|
          # Consume any consecutive deletion edits from the current diff.
          consume_deletions(diff, i) { |row| yield row }
        end

        # if all diffs have been consumed, exit the loop
        return if complete?
        
        # Get the next edit from each diff, based on current offsets.
        edits = offset_diffs.map { |offset, diff| diff[offset] }
        @offsets.map! { |offset| offset + 1 } # Increment all offsets by 1. 

        yield Row.new(edits)
      end
    end

    # Consume consecutive deletion edits from the given diff, starting from the given offset.
    # @param diff [Array<Edit>] The diff to consume edits from.
    # @param i [Integer] The index of the diff in the `@diffs` array.
    def consume_deletions(diff, i)
      # Loop while the offset is within the bounds of the diff, and the current edit is a deletion.
      while @offsets[i] < diff.size && diff[@offsets[i]].type == :del
        edits = Array.new(@diffs.size) # Create an array of edits, with a size equal to the number of diffs.
        edits[i] = diff[@offsets[i]] # Set the edit at the current diff's index to the current deletion edit.
        @offsets[i] += 1

        yield Row.new(edits) # Yield a new `Row` object containing the deletion edit.
      end
    end

    # Returns a list of pairs of [offset, diff] using Enumerable#zip
    def offset_diffs
      @offsets.zip(@diffs)
    end

    # Returns true if all the offsets are equal to the corresponding diff`s size.
    def complete?
      offset_diffs.all? { |offset, diff| offset == diff.size}
    end

  end
end