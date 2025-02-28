
module Pack 
  HEADER_SIZE = 12
  HEADER_FORMAT = "a4N2"
  SIGNATURE = "PACK"
  VERSION = 2

  COMMIT = 1
  TREE = 2
  BLOB = 3

  TYPE_CODES = {
    "commit" => COMMIT, 
    "tree" => TREE, 
    "blob" => BLOB
  }

  MAX_COPY_SIZE = 0xffffff # Maximum space allocated for the size of copy operation i.e 3 bytes
  MAX_INSERT_SIZE = 0x7f # Maximum space allocated for the size of inser operation i.e 7 bits

  Record = Struct.new(:type, :data) do 
    attr_accessor :oid

    def to_s
      data
    end
  end

end