
class Tempfile
  # Characters used for generating temporary filenames
  TEMP_CHARS = ("a".."z").to_a + ("A".."Z").to_a + ("0".."9").to_a

  def initialize(dirname, prefix)
    @dirname = dirname
    @path = @dirname.join(generate_temp_name)
    @file = nil
  end

  # Generates a random temporary filename
  # @return [String] Random filename in format "tmp_obj_XXXXXX"
  def generate_temp_name
    "tmp_obj_#{(1..6).map {TEMP_CHARS.sample}.join("") }"
  end

  def write(data)
    open_file if !@file
    @file.write(data)
  end

  def move(name)
    @file.close
    File.rename(@path, @dirname.join(name))
  end

  def open_file
    flags = File::RDWR | File::CREAT | File::EXCL
    @file = File.open(@path, flags)
  rescue Errno::ENOENT
    # Create directory if it doesn't exist and retry
    Dir.mkdir(@dirname)
    retry
  end

 
end