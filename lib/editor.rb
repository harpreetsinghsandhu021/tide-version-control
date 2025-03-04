require "shellwords"

# Editor class handles file editing operations with external text editors
# and provides methods for file manipulation with comment handling
class Editor 
  # Default editor to use if none specified
  DEFAULT_EDITOR = "vi"

  # Class method to handle file editing operations
  # @param path [String] Path to the file to edit
  # @param command [String] Editor command to use
  # @yield [Editor] Yields the editor instance
  # @return [String, nil] Edited file contents with comments removed
  def self.edit(path, command)
    editor = Editor.new(path, command)
    yield editor
    editor.edit_file
  end

  # Initializes a new Editor instance
  # @param path [String] Path to the file to edit
  # @param command [String] Editor command to use, defaults to DEFAULT_EDITOR
  def initialize(path, command)
    @path = path
    @command = command || DEFAULT_EDITOR
    @closed = false
  end

  # Writes a string to the file
  # @param string [String] Content to write
  # @return [nil] if file is closed
  def puts(string)
    return if @closed
    file.puts(string)
  end

  # Writes a string as comments to the file
  # @param string [String] Content to write as comments
  # @return [nil] if file is closed
  def note(string)
    return if @closed
    string.each_line { |line| file.puts("# #{ line }")}
  end

  # Marks the editor as closed
  def close 
    @closed = true
  end

  # Gets or creates the file handle for writing
  # @return [File] File handle with write permissions
  def file 
    flags = File::Constants::WRONLY | File::Constants::CREAT | File::Constants::TRUNC
    @file ||= File.open(@path, flags)
  end

  # Launches external editor and processes the edited content
  # @raise [RuntimeError] if editor command fails
  # @return [String, nil] Edited file contents with comments removed
  def edit_file
    file.close
    editor_argv = Shellwords.shellsplit(@command) + [@path.to_s]

    unless @closed || system(*editor_argv)
      raise "There was a problem with the editor '#{ @command }'."
    end

    remove_notes(File.read(@path))
  end

  # Removes comment lines from the input string
  # @param string [String] Content to process
  # @return [String, nil] Processed content without comments, nil if empty
  def remove_notes(string)
    lines = string.lines.reject { |line| line.start_with?("#")}

    if lines.all? { |line| /^\s*$/ =~ line }
      nil
    else 
      "#{ lines.join("").strip }\n"
    end
  end

  
end