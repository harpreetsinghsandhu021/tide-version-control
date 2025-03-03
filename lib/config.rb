class Config 
  # The Config class handles reading and parsing of configuration files.
  # It provides functionality to manage configuration sections, variables,
  # and their values while maintaining file-level locking for concurrent access.

  SECTION_LINE = /\A\s*\[([a-z0-9-]+)( "(.+)")?\]\s*(\Z|#|;)/i
  VARIABLE_LINE = /\A\s*([a-z][a-z0-9-]*)\s*=\s*(.*?)\s*(\Z|#|;)/im
  BLANK_LINE = /\A\s*(\Z|#|;)/
  INTEGER = /\A-?[1-9][0-9]*\Z/

  VALID_SECTION  = /^[a-z0-9-]+$/i
  VALID_VARIABLE = /^[a-z][a-z0-9-]*$/i

  ParseError = Class.new(StandardError)
  Conflict = Class.new(StandardError)

  # Represents a configuration variable with a name and value.
  # Provides methods for normalizing names and serializing variables.
  Variable = Struct.new(:name, :value) do 
    # Normalizes variable names by converting them to lowercase
    # @param name [String] the variable name to normalize
    # @return [String, nil] the normalized name or nil if input is nil
    def self.normalize(name)
      name&.downcase
    end
  
    # Serializes a variable name and value into a config file format
    # @param name [String] the variable name
    # @param value [String] the variable value
    # @return [String] formatted config line with indentation
    def self.serialize(name, value)
      "\t#{ name } = #{ value }\n"
    end
  end

  def self.valid_key?(key)
    VALID_SECTION =~ key.first && VALID_VARIABLE =~ key.last
  end

  # Represents a configuration section with hierarchical naming support
  Section = Struct.new(:name) do 
    # Normalizes section names into a standardized format
    # @param name [Array<String>] array of section name components
    # @return [Array] normalized section identifier
    def self.normalize(name)
      return [] if name.empty?
      [name.first.downcase, name.drop(1).join(".")]
    end

    # Generates the section header line for the config file
    # @return [String] formatted section header
    def heading_line
      line = "[#{ name.first }"
      line.concat(%' "#{ name.drop(1).join(".") }"') if name.size > 1
      line.concat("]\n")
    end
  end

  # Represents a single line in the configuration file
  Line = Struct.new(:text, :section, :variable) do
    # Returns the normalized variable name for the line
    # @return [String, nil] normalized variable name or nil if no variable
    def normal_variable
      Variable.normalize(variable&.name)
    end
  end

  # Initializes a new Config instance
  # @param path [String] path to the configuration file
  def initialize(path)
    @path = path.to_s
    @lockfile = Lockfile.new(path)
    @lines = nil
  end
  
  # Opens and reads the configuration file if not already loaded
  def open
    read_config_file if !@lines
  end

  # Acquires a lock and opens the file for updating
  # This ensures thread-safe access to the configuration file
  def open_for_update
    @lockfile.hold_for_update
    read_config_file
  end

  # Reads and parses the configuration file into memory
  # Creates a hash of sections containing their respective lines
  # @private
  def read_config_file
    @lines = Hash.new { |hash, key| hash[key] = []}
    section = Section.new([])

    File.open(@path, File::RDONLY) do |file|
      until file.eof?
        line = parse_line(section, read_line(file)) 
        section = line.section
        lines_for(section).push(line)
      end   
    end
  rescue Errno::ENOENT
    # Handle case when file doesn't exist
  end

  # Reads a line from the file, handling line continuations
  # @param file [File] the file being read
  # @return [String] complete line including any continuations
  # @private
  def read_line(file)
    buffer = ""

    loop do 
      buffer.concat(file.readline)
      # puts buffer
      return buffer if !buffer.end_with?("\\\n")
    end
  end

  # Returns the array of lines for a given section
  # @param section [Section] the section whose lines are requested
  # @return [Array<Line>] array of lines in the section
  # @private
  def lines_for(section)
    @lines[Section.normalize(section.name)]
  end

  # Uses Regex patterns to classify each line as either a section heading, a variable
  # or a blank line.
  def parse_line(section, line)
    # Try to match line against section header pattern
    

    if match = SECTION_LINE.match(line)
      # Create new section if match found, combining primary name and optional subsection
      section = Section.new([match[1], match[3]].compact)
      Line.new(line, section)
    elsif match = VARIABLE_LINE.match(line)
      # If line matches variable pattern, create new Variable with parsed name and value
      variable = Variable.new(match[1], parse_value(match[2]))
      Line.new(line, section, variable)
    elsif match = BLANK_LINE.match(line)
      # Handle blank lines or comment lines
      Line.new(line, section, nil)
    else 
      # Raise error for malformed lines
      message = "bad config line #{ line_count + 1} in file #{ @path }"
      raise ParseError, message
    end
  end
  

  def line_count
    # Calculate total number of lines across all sections
    # Reduces each section's line count into a single sum
    @lines.each_value.reduce(0) { |n, lines| n + lines.size }
  end 

  def parse_value(value)
    # Convert string values to appropriate data types
    # Handles boolean (yes/no, on/off, true/false)
    # Handles integers and multiline values
    case value 
    when "yes", "on", "true" then true
    when "no", "off", "false" then false
    when INTEGER then value.to_i
    else
      # Remove line continuation markers
      value.gsub(/\\\n/, "")
    end
  end

  # Saves the current configuration state to the file
  # Writes all lines from memory back to disk and commits changes
  def save
    # Write all lines back to the config file
    # Iterates through each section and its lines
    @lines.each do |section, lines|
      lines.each { |line| @lockfile.write(line.text) }
    end
    # Commit changes to disk
    @lockfile.commit
  end

  # Splits a composite key into section and variable parts
  # @param key [Array<String>] the composite key to split
  # @return [Array] array containing [section_array, variable_name]
  def split_key(key)
    # Separate a key into section and variable components
    # Example: ['core', 'editor'] becomes (['core'], 'editor')
    key = key.map(&:to_s)
    var = key.pop
    [key, var]
  end

  # Finds all lines in a section matching a specific variable
  # @param key [Array<String>] section identifier
  # @param var [String] variable name to find
  # @return [Array] array containing [Section, Array<Line>]
  def find_lines(key, var)
    # Locate all lines in a section matching the given variable name
    # Returns the section and matching lines as an array
    name = Section.normalize(key)
    return [nil, []] if !@lines.has_key?(name)

    lines = @lines[name]
    section = lines.first.section
    normal = Variable.normalize(var)
    lines = lines.select { |l| normal == l.normal_variable }
    [section, lines]
  end

  # GETTER METHODS
  
  # Retrieves all values associated with a specific key
  # @param key [Array<String>] the key to look up
  # @return [Array] array of values matching the key
  def get_all(key)
    # Retrieve all values for a given key
    # Returns array of values matching the key
    key, var = split_key(key)
    _, lines = find_lines(key, var)
    lines.map { |line| line.variable.value }
  end

  # Gets the most recent value for a given key
  # @param key [Array<String>] the key to look up
  # @return [Object, nil] the last value set for the key or nil if not found
  def get(key)
    # Get the most recently set value for a key
    # Returns nil if key doesn't exist
    get_all(key).last
  end

  # Adds a new value to the configuration
  # @param key [Array<String>] the key to add
  # @param value [Object] the value to associate with the key
  def add(key, value)
    # Add a new value to the configuration
    # Creates new section if necessary
    key, var = split_key(key)
    section, _ = find_lines(key, var)
    add_variable(section, key, var, value)
  end

  # Adds a new variable to a section
  # @param section [Section] the section to add to
  # @param key [Array<String>] the section identifier
  # @param var [String] variable name
  # @param value [Object] value to set
  # @return [Line] the newly created line
  def add_variable(section, key, var, value)
    # Helper method to add a new variable to a section
    # Creates new section if one doesn't exist
    section ||= add_section(key)
    text = Variable.serialize(var, value)
    var = Variable.new(var, value)
    line = Line.new(text, section, var)
    lines_for(section).push(line)
  end

  # Updates an existing variable's value and text representation
  # @param line [Line] the line to update
  # @param var [String] the variable name
  # @param value [Object] the new value
  def update_variable(line, var, value)
    # Update existing variable's value and text representation
    line.variable.value = value
    line.text = Variable.serialize(var, value)
  end

  # Creates a new section in the configuration
  # @param key [Array<String>] the section identifier
  # @return [Section] the newly created section
  def add_section(key)
    # Create a new section in the config file
    # Returns the newly created section
    section = Section.new(key)
    line = Line.new(section.heading_line, section)
    lines_for(section).push(line)
    section
  end

  # Sets a single value for a key, ensuring no duplicates exist
  # @param key [Array<String>] the key to set
  # @param value [Object] the value to set
  # @raise [Conflict] if multiple values exist for the key
  def set(key, value)
    # Set a single value for a key
    # Raises Conflict error if multiple values exist
    key, var = split_key(key)
    section, lines = find_lines(key, var)

    case lines.size
    when 0 then add_variable(section, key, var, value)
    when 1 then update_variable(lines.first, var, value)
    else
      message = "cannot overwrite multiple values with a single value"
      raise Conflict, message
    end
  end 

  # Replaces all existing values for a key with a new value
  # @param key [Array<String>] the key to replace
  # @param value [Object] the new value to set
  def replace_all(key, value)
    # Remove all existing values for a key and set a new value
    key, var = split_key(key)
    section, lines = find_lines(key, var)
    remove_all(section, lines)
    add_variable(section, key, var, value)
  end

  # Removes all specified lines from a section
  # @param section [Section] the section containing the lines
  # @param lines [Array<Line>] the lines to remove
  def remove_all(section, lines)
    # Remove all specified lines from a section
    lines.each { |line| lines_for(section).delete(line) }
  end

  # Removes all variables matching the key
  # @param key [Array<String>] the key to unset
  # @yield [Array<Line>] optionally yields removed lines to a block
  def unset_all(key)
    # Remove all variables matching the key
    # Optionally yields removed lines to a block
    # Removes section if empty after unset
    key, var = split_key(key)
    section, lines = find_lines(key, var)
    return if !section
    yield lines if block_given?
    remove_all(section, lines)
    lines = lines_for(section)
    remove_section(key) if lines.size == 1
  end

  # Removes an entire section from the configuration
  # @param key [Array<String>] the section identifier to remove
  # @return [Boolean] true if section was removed, false if it didn't exist
  def remove_section(key)
    # Remove an entire section from the configuration
    # Returns true if section was removed, false if it didn't exist
    key = Section.normalize(key)
    @lines.delete(key) ? true : false
  end

  # Unsets a single key, ensuring no duplicates exist
  # @param key [Array<String>] the key to unset
  # @raise [Conflict] if multiple values exist for the key
  def unset(key)
    unset_all(key) do |lines|
      raise Conflict,"#{ key } has multiple values"  if lines.size > 1
    end
  end

  # Returns all subsections for a given section name
  # @param name [String] the section name
  # @return [Array<String>] array of subsection names
  def subsections(name)
    name, _ = Section.normalize([name])
    sections = []

    @lines.each_key do |main, sub|
      sections.push(sub) if main == name and sub != ""
    end

    sections
  end

  # Checks if a section exists in the configuration
  # @param key [Array<String>] the section identifier to check
  # @return [Boolean] true if section exists, false otherwise
  def section?(key)
    key = Section.normalize(key)
    @lines.has_key?(key)
  end

end