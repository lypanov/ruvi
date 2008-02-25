require "debug.rb"

module Ruvi

class Highlighters
    include Singleton
    attr_accessor :registered_highlighters
    def initialize
        @registered_highlighters = []
    end
    def register_highlighter highlighter
        @registered_highlighters << highlighter
    end
end

class Highlighter
    def self.has_structure?
        false
    end
    def Highlighter.inherited sub
        Highlighters::instance.register_highlighter sub
    end
end

end

