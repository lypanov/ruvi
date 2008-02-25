module Ruvi

Point = Struct.new :x, :y
class Point
    include Comparable
    def nil?
        self.x.nil? || self.y.nil?
    end
    def == b
        a = self
        a.x == b.x and a.y == b.y
    end
    def > b
        raise "comparison against nil" if b.nil? # temp work around for crap thread debugging
        a = self
        (a.y > b.y) || (a.y == b.y && a.x > b.x)
    end
end

module NewLineAttributes
   attr_accessor :newline_at_start, :newline_at_end
   def inspect
       super + " (#{newline_at_start}-S:#{newline_at_end}-E)"
   end
end

end
