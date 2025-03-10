
module Merge
  class Inputs 

    ATTRS = [:left_name, :right_name, :left_oid, :right_oid, :base_oids]
    attr_reader(*ATTRS)
    

    def initialize(repository, left_name, right_name)
      @repo = repository
      @left_name = left_name
      @right_name = right_name

      @left_oid = resolve_rev(@left_name)
      @right_oid = resolve_rev(@right_name)

      common = Bases.new(@repo.database, @left_oid, @right_oid)
      @base_oids = common.find
    end

    private

    def resolve_rev(rev)
      Revision.new(@repo, rev).resolve(Revision::COMMIT)
    end

    # If returns true, the merge class can bail out before trying to make any changes.
    def already_merged?
      @base_oids == [@right_oid]
    end

    def fast_forward?
      @base_oids == [@left_oid]
    end

  end

  CherryPick = Struct.new(*Inputs::ATTRS)

end