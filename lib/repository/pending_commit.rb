class Repository
  class PendingCommit
    # Manages the storage and retrieval of these saved merge values, and lets us check 
    # whether a merge is currently in progress. It saves off the commit
    # ID and message passed to it into the files .git/MERGE_HEAD and .git/MERGE_MSG.
    
    Error = Class.new(StandardError)

    attr_reader :message_path

    def initialize(pathname)
      @head_path = pathname.join("MERGE_HEAD")
      @message_path = pathname.join("MERGE_MSG")
    end

    def start(oid, message)
      flags = File::Constants::WRONLY | File::Constants::CREAT | File::Constants::EXCL

      File.open(@head_path, flags) { |f| f.puts(oid) }
      File.open(@message_path, flags) { |f| f.write(message) }
    end

    def clear 
      File.unlink(@head_path)
      File.unlink(@message_path)
    rescue Errno::ENOENT
      name = @head_path.basename
      raise Error, "There is no merge to abort (#{ name } missing)."
    end

    # Returns true if a merge is unfinished, which we can detect by checking 
    # whether .git/MERGE_HEAD exist.
    def in_progress?
      File.file?(@head_path)
    end

    def merge_oid
      File.read(@head_path).strip
    rescue Errno::ENOENT
      name = @head_path.basename
      raise Error, "There is no merge in progress (#{ name } missing)."
    end

    def merge_message
      File.read(@message_path)
    end

  end
end