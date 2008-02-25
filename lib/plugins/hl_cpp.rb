module Ruvi

class CPPHighlighter < Highlighter
    def self.importance
        0
    end
    def self.can_highlight? buffer
        return (buffer.fname =~ /\.cpp$/)
    end
    def get_highlight_state buf, y
        buf.hlstacks[y]
    end
    def should_continue_highlight_pass? buf, y, state
        buf.hlstacks[y] != state
    end
    def highlight_line buf, line, ypos
        hl_stack = (ypos == 0) ? [] : buf.hlstacks[ypos - 1].dup rescue [] # HACK
        current_class_stack = buf.classstacks[ypos-1]
        current_class_stack = current_class_stack.nil? ? [] : current_class_stack.dup
        dbg(:dbg_highlight) { "-#- #{line} #{ypos} #{hl_stack.inspect}" }
        s = StringScanner.new line
        while !s.eos?
            state = :normal
            state = :string if hl_stack.last == '"'
            state = :comment if hl_stack.last == '/*'
            case state
            when :comment
                matched = s.scan(/(\*\/|[^*]+|\*)/)
                dbg(:dbg_highlight) { matched.inspect }
                bold = true
                color = Curses::COLOR_CYAN
                hl_stack.pop if matched == "*/"
                yield color, bold, matched if block_given?
            when :string
                matched = s.scan(/("|[^"]+)/)
                dbg(:dbg_highlight) { matched.inspect }
                bold = true
                color = Curses::COLOR_MAGENTA
                hl_stack.pop if matched == "\""
                yield color, bold, matched if block_given?
            when :normal
                matched = s.scan(/(\/\/.*$|\/\*|\w+|\s+|.)/)
                dbg(:dbg_highlight) { matched.inspect }
                bold = nil
                color = Curses::COLOR_WHITE
                case matched
                when /\/\/.*$/
                    color = Curses::COLOR_CYAN
                    bold = true
                when /[0-9]/
                    color = Curses::COLOR_MAGENTA
                    bold = true
                when *%w(if)
                    color = Curses::COLOR_YELLOW
                    bold = true
                when *%w(void int char)
                    color = Curses::COLOR_GREEN
                    bold = true
                when /\w+/
                    color = Curses::COLOR_WHITE
                when "{"
                    hl_stack.push "{"
                when "}"
                    hl_stack.pop
                when "("
                    hl_stack.push "("
                when ")"
                    hl_stack.pop
                when "\""
                    bold = true
                    color = Curses::COLOR_MAGENTA
                    hl_stack.push "\""
                when "/*"
                    bold = true
                    color = Curses::COLOR_CYAN
                    hl_stack.push "/*"
                end
                bold = false unless !bold.nil?
                yield color, bold, matched if block_given?
            end
            dbg(:dbg_highlight) { "STATE : #{hl_stack.inspect} : #{state}" }
        end
        buf.classstacks[ypos] = current_class_stack
        buf.hlstacks[ypos]    = hl_stack
    end
end

end
