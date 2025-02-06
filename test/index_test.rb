require "minitest/autorun"
require "pathname"
require "securerandom"
require "index"

# Defines a Minitest test suite for an 'Index' class
describe Index do 
  # Set up common objects used in the tests 
  let(:tmp_path) {File.expand_path("../../tmp", __FILE__)} # Path to tmp directory
  let(:index_path) {Pathname.new(tmp_path).join("index")} # Path to an "index" file
  let(:index) {Index.new(index_path)} # An instance of the index class
  let(:stat) {File.stat(__FILE__)} # File stats of the current file
  let(:oid) {SecureRandom.hex(20)} # A random object ID (40 hex characters)

  # Define a test case:
  it "adds a single file" do 
    # Call the 'add' method to add a file entry to the database
    index.add('alice.txt', oid, stat)

    # Assert that the index now contains the added file
    assert_equal ["alice.txt"], index.each_entry.map(&:path)
  end

  it "replaces a file with a directory" do 
    # Arrange
    index.add("alice.txt", oid, stat)
    index.add("bob.txt", oid, stat)

    # Act
    index.add("alice.txt/nested.txt", oid, stat)

    # Assert
    assert_equal ["alice.txt/nested.txt", "bob.txt"], index.each_entry.map(&:path)
  end

  it "replaces a directory with a file" do
    index.add('alice.txt', oid, stat)
    index.add('nested/bob.txt', oid, stat)

    index.add('nested', oid, stat)

    assert_equal ["alice.txt", "nested"], index.each_entry.map(&:path)
  end

  it "recursively replaces a directory with a file" do 
    index.add('alice.txt', oid, stat)
    index.add('nested/bob.txt', oid, stat)
    index.add("nested/inner/claire.txt", oid, stat)

    index.add("nested", oid, stat)

    assert_equal ["alice.txt","nested"], index.each_entry.map(&:path)
  end

end
