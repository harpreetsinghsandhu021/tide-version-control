require_relative "./diff/myers"
require_relative "./diff/hunk"


module Diff 
  # Module for handling file difference comparisons
  # Implements functionality to compare text files and generate diff output 
  
  
  # Symbols used to represent different types of changes in the diff output
  # ' ' for unchanged lines, '+' for insertions, '-' for deletions
  SYMBOLS = { 
    :eql => " ", # Equal/unchanged lines
    :ins => "+", # Inserted lines
    :del => "-"  # Deleted lines
  }

  # Struct to represent a line in a file
  # number: line number in the file
  # text: content of the line
  Line = Struct.new(:number, :text)

  # Struct to represent an edit operation in the diff
  # type: the type of edit (:eql, :ins, or :del)
  # a_line: line from the first file (source)
  # b_line: line from the second file (target)
  Edit = Struct.new(:type, :a_line, :b_line) do 
    # Convert edit to string representation with appropriate symbol
    def to_s
      line = a_line || b_line 
      SYMBOLS.fetch(type) + line.text
    end

    def a_lines
      [a_line]
    end
  end

  # Converts a document (string or array) into an array of Line objects
  # @param document [String, Array] the input document
  # @return [Array<Line>] array of Line objects with line numbers
  def self.lines(document)
    document = document.lines if document.is_a?(String)
    document.map.with_index { |text, i| Line.new(i + 1, text)}
  end

  # Generate diff between two documents using Myers difference algorithm
  # @param a [String, Array] first document
  # @param b [String, Array] second document
  # @return [Array<Edit>] array of edit operations
  def self.diff(a, b)
    Myers.diff(Diff.lines(a), Diff.lines(b))
  end

  # Generate diff hunks between two documents
  # Hunks are groups of changes that are close to each other
  # @param a [String, Array] first document
  # @param b [String, Array] second document
  # @return [Array<Hunk>] array of diff hunks
  def self.diff_hunks(a,b)
    Hunk.filter(Diff.diff(a, b))
  end

  # Generate combined diff for multiple source documents against one target
  # @param as [Array<String, Array>] array of source documents
  # @param b [String, Array] target document
  # @return [Array] combined diff results
  def self.combined(as, b)
    diffs = as.map { |a| Diff.diff(a, b) }
    Combined.new(diffs).to_a
  end

  # Generate Hunk-filtered combined diff from a list of pre merge versions and a merge result.
  def self.combined_hunks(as, b)
    Hunk.filter(Diff.combined(as, b))
  end
end

# Example usage (commented out):
# a = "ABCABBA".chars
# b = "CBABAC".chars
# edits = Diff.diff(a, b)
# edits.each { |edit| puts edit }