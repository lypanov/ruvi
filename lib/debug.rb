# globally available - TODO - can't this be namespaced?
def dbg dbg_sym, &block
    Ruvi::Debug::instance.dbg(dbg_sym, &block)
end

def dbg_on dbg_sym
    Ruvi::Debug::instance.debug_symbols << dbg_sym
end

module Ruvi

class EditorApp
    def show_line_with_marker buffer, point, line = nil
        line = buffer.lines[point.y] if line.nil?
        n = 0
        line.unpack("c*").collect { 
                            |c| 
                            t = (n == point.x) ? "[#{c.chr}]"  \
                                                : "#{c.chr}"
                            n += 1; t 
                            }.join
    end
    
    def dbg_selc buffer, selc
        dbg(:selc) { selc}
        dbg(:selc) { show_line_with_marker buffer, selc.s }
        dbg(:selc) { show_line_with_marker buffer, selc.e }
    end
end

class Debug
    include Singleton

    attr_accessor :debug_symbols 

    def initialize
        @debug_symbols = []
    end

    def register_debug_buffer buffer
        @debug_buffer = buffer
    end

    def dbg dbg_sym, &block
        return if !dbg_sym.nil? and @debug_symbols.empty?
        return if !dbg_sym.nil? and !(@debug_symbols.include? dbg_sym)
        str = block.call
        line = (str.is_a? String) ? str : str.inspect
        if $test_case
            puts line
            return
        end
        @debug_buffer.lines << BufferLine.new(line)
    end
end

end
