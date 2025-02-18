
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

  Record = Struct.new(:type, :data) do 
    attr_accessor :oid

    def to_s
      data
    end
  end

end