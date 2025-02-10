module Merge
  class Diff3
    # Implements the 3-way merge algorithmn. It takes three texts as an input:
    # * o: the original text
    # * a: the first modified text
    # * b: the second modified text



    # Clean struct represents sections of text that have no conflicts
    # Used when changes from different sources don't overlap or one source matches the original
    Clean = Struct.new(:lines) do 
      def to_s(*)
        lines.join("")
      end
    end

    # Conflict struct represents sections where all three versions differ
    # Contains the lines from all three versions: original, modification A, and modification B
    Conflict = Struct.new(:o_lines, :a_lines, :b_lines) do 
      # Formats the conflict in Git-style merge conflict markers
      # a_name and b_name are optional branch/file names to show in conflict markers
      def to_s(a_name = nil, b_name = nil)
        text = ""
        seperator(text, "<", a_name)      # Adds <<<<<<< marker
        a_lines.each { |line| text.concat(line) }
        seperator(text, "=")              # Adds ======= marker
        b_lines.each { |line| text.concat(line) }
        seperator(text,">", b_name)       # Adds >>>>>>> marker
        text
      end

      # Helper method to create conflict markers
      # Creates markers like: <<<<<<< branch_name
      #                      =======
      #                      >>>>>>> branch_name
      def seperator(text, char, name=nil)
        text.concat(char * 7)
        text.concat(" #{ name }") if name
        text.concat("\n")
      end
    end

    # Result struct represents the final merged output
    # Contains an array of Clean and Conflict chunks
    Result = Struct.new(:chunks) do 
      # Returns true if there are no conflicts in the merged result
      def clean? 
        chunks.none? { |chunk| chunk.is_a?(Conflict)}
      end

      # Converts all chunks to string format
      # Passes branch/file names to conflict markers if provided
      def to_s(a_name=nil, b_name=nil)
        chunks.map { |chunk| chunk.to_s(a_name, b_name) }.join("")
      end
    end



    # Takes three texts as input, ensures they are arrays of lines, and then creates a diff3 
    # object to perform the merge.
    # @param o [String or Array<String>] the original text
    # @param a [String or Array<String>] the first modified text
    # @param b [String or Array<String>] the second modified text
    def self.merge(o, a ,b)

      o = o.lines if o.is_a?(String)
      a = a.lines if a.is_a?(String)
      b = b.lines if b.is_a?(String)

      Diff3.new(o, a, b).merge
    end

    def initialize(o, a ,b)
      @o, @a, @b = o, a, b
    end

    # Performs 3-way merge operation
    def merge 
      setup 
      generate_chunks
      Result.new(@chunks)
    end

    def setup
      @chunks = []
      @line_o = @line_a = @line_b = 0
      @match_a = match_set(@a)
      @match_b = match_set(@b)
    end
  
    # Computes a map from line numbers in the given file to the corresponding line numbers in the original text.
    # @param file [Array<String>] the file to compute the map for
    # @return [Hash<Integer, Integer>] a map from line numbers in the file to the corresponding line numbers in the original text
    def match_set(file)
      matches = {}

      Diff.diff(@o, file).each do |edit|
        next if edit.type != :eql
        matches[edit.a_line.number] = edit.b_line.number
      end

      matches
    end

    # Generates the chunks of the merged text.
    def generate_chunks
      loop do 
        i = find_next_mismatch # Find the next line number where the three files differ. 

        if i == 1 # If the mismatch is on the very next line... 
          o, a, b = find_next_match # Find the next point where all three files agree again. 

          if a && b # If such a point is found... 
            emit_chunk(o, a, b) # Emit a chunk from the current position to the matching point
          else # Otherwise... 
            emit_final_chunk # Emit a final chunk containing any remaining lines. 
            return # And exit the loop, as there are no more matches. 
          end
        elsif i # If a mismatch was found but it`s not on the very next line... 
          emit_chunk(@line_o + i, @line_a + i, @line_b + i) # Emit a chunk up to the point of the mismatch.
        else # If no mismatch was found at all... 
          emit_final_chunk # Emit a final chunk containing any remaining lines. 
          return
        end
      end
    end

    def find_next_mismatch
      i = 1

      while in_bounds?(i) && match?(@match_a, @line_a, i) && match?(@match_b, @line_b, i)
        i += 1
      end
      
      in_bounds?(i) ? i : nil
    end

    # Find the start of the next match.
    def find_next_match
      o = @line_o + 1
      until o > @o.size || (@match_a.has_key?(o) && @match_b.has_key?(o))
        o += 1
      end

      [o, @match_a[o], @match_b[o]]
    end

    def in_bounds(i)
      @line_o + i <= @o.size || @line_a + i <= @a.size || @line_b <= @b.size
    end

    # Determines if a specific line in the original document has a corresponding, unchanged line in the modified
    # document.
    # @param matches: this is the match set for the document you are currently comparing.
    # @param offset: represents the starting line number relative to the current chunk being examined.
    # @param i: An increment from the offset used to check subsiquent lines.
    def match?(matches, offset, i)
      matches[@line_o + i] == offset + i
    end

    def emit_chunk(o, a, b)
    end

    # Takes a set of lines from each document and emits the appropriate kind of chunk depending on their contents.
    def write_chunk(o, a, b)
      if a == o || a == b
        # If 'a' matches either original or 'b', use 'b' as there's no real conflict
        @chunks.push(Clean.new(b))
      elsif b == o 
        # If 'b' matches original, use 'a' as it's the only change
        @chunks.push(Clean.new(a))
      else 
        # All three versions are different, create a conflict
        @chunks.push(Conflict.new(o, a, b))
      end
    end      

  end
end