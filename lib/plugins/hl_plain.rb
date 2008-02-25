require "debug.rb"

module Ruvi

class PlainTextHighlighter < Highlighter
    def self.importance
        -100
    end
    def get_highlight_state buf, y
        # we don't need a highlight state....
        nil
    end
    def should_continue_highlight_pass? buf, y, state
        false
    end
    def self.can_highlight? buffer
        true
    end
    def highlight_line buf, line, ypos
        yield Curses::COLOR_WHITE, true, line if block_given?
    end
end

end
