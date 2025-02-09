class Index

  ENTRY_FORMAT = "N10H40nZ*" # Format in which git saves data in the .git/index file
  ENTRY_BLOCK = 8

  REGULAR_MODE = 0100644
  EXECUTABLE_MODE = 0100755
  MAX_PATH_SIZE = 0xfff


  entry_fields = [
    :ctime, :ctime_nsec, 
    :mtime, :mtime_nsec, 
    :dev, :ino, :mode, :uid, :gid, :size, 
    :oid, :flags, :path
  ]

  Entry = Struct.new(*entry_fields) do 
    def self.create(pathname, oid, stat) # class method
      path = pathname.to_s
      mode = Entry.mode_for_stat(stat)
      flags = [path.bytesize, MAX_PATH_SIZE].min

      new( 
        stat.ctime.to_i, stat.ctime.nsec, 
        stat.mtime.to_i,  stat.mtime.nsec, 
        stat.dev, stat.ino, mode, stat.uid, stat.gid, stat.size, 
        oid, flags, path
      )
    end

    def self.mode_for_stat(stat)
      stat.executable? ? EXECUTABLE_MODE : REGULAR_MODE
    end

    def times_match?(stat)
      ctime == stat.ctime.to_i and ctime_nsec == stat.ctime.nsec and 
      mtime == stat.mtime.to_i and mtime_nsec == stat.mtime.nsec
    end

    def to_s
      # Calling to_a returns an array of the values of all its fields, in the order they are defined in the struct.new.
      string = to_a.pack(ENTRY_FORMAT) 
      string.concat("\0") until string.bytesize % ENTRY_BLOCK == 0
      string
    end

    def update_stat(stat)
      self.ctime = stat.ctime.to_i
      self.ctime_nsec = stat.ctime.nsec 
      self.mtime =  stat.mtime.to_i  
      self.mtime_nsec =  stat.mtime.nsec 
      self.dev =  stat.dev
      self.ino =  stat.ino
      self.mode = Entry.mode_for_stat(stat) 
      self.uid =  stat.uid
      self.gid =    stat.gid
      self.size =    stat.size
    end 

    def key 
      [path, stage] 
    end

    # Extracting an entry`s stage from its flags number
    def stage
      # bit shifting the value by 12 places, and selecting the two least significant digits
      (flags >> 12) & 0x3
    end

    def self.parse(data)
      new(*data.unpack(ENTRY_FORMAT))
    end

    def self.create_from_db(pathname, item, n)
      path = pathname.to_s

      # Used to pack two pieces of information into the flags field of an Index::Entry:, 
      # The n value represents the merge stage of the entry (1 for common ancestor, 2 for "ours", 3 for "theirs"). 
      # Shifting it left by 12 bits (n << 12) positions it in the higher bits of the flags field.
      # [path.bytesize, MAX_PATH_SIZE].min calculates the length of the file path, capped at MAX_PATH_SIZE.
      # This length is stored in the lower bits of the flags field.
      # Bitwise OR (|) combines these two values, placing the stage in the higher bits and the path length in the lower bits. 
      # This efficiently stores both pieces of data within a single integer field.
      flags = (n << 12) | [path.bytesize, MAX_PATH_SIZE].min

      # Many of the timestamp and stat fields are set to 0 because they are not relevant for conflict entries.
      # IMPORTANT - The calculated flags value (containing the stage and path length information).
      Entry.new(0, 0, 0, 0, 0, 0, item.mode, 0, 0, 0,item.oid, flags, path)
    end

    def parent_directories
      Pathname.new(path).descend.to_a[0..-2]
    end
    
    def basename
      Pathname.new(path).basename 
    end

    def stat_match?(stat)
      mode == Entry.mode_for_stat(stat) and (size == 0 or size == stat.size)
    end

  end

 
end