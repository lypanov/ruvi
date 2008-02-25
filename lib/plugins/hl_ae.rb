require '3rdparty/aelexer/lexer.rb'

class AELog2RuviLog
    def debug code, &block
        dbg code, &block
    end
end

module Ruvi

class AELexerHighlighter < Highlighter
    RUBY_BLOCK_START_KEYWORDS = %w(while until if loop when unless else elsif return yield rescue case for begin ensure next break raise)
    RUBY_STRUCTURE_START_KEYWORDS = %w(class module def)
    RUBY_STRING_BLOCKS = {"=begin" => "=end", "%{" => "}", "%w(" => ")"}
    RUBY_BLAH = %w(def class include require module)
    RUBY_DO_NOT_PUSH_KEYWORDS = %w(when else elsif return yield ensure rescue next break raise do)
    HlElement = Struct.new :str, :x
    def matches_hash
        { "{" => "}",  "(" => ")", 
          "def" => "end", "module" => "end", "class" => "end",
          "if" => "end", "while" => "end", "begin" => "end", "until" => "end", 
          "loop" => "end", "unless" => "end", "case" => "end", "for" => "end", "do" => "end"
        }
    end
    def initialize
        @lexer = LexerRuby::Lexer.new
        @aelexer_state_cache_per_buffer = {}
        $logger = AELog2RuviLog.new
    end
    def self.importance
        800
    end
    def self.has_structure?
        false
    end
    # test - lots of example ruby code... need rendering for proper testing
    def self.can_highlight? buffer
        return (buffer.fname =~ /\.(rb|gemspec)$/) || (buffer.lines.first =~ /^#\!.*ruby.*/)
    end
    def get_highlight_state buf, y
        buf.hlstacks[y]
    end
    def should_continue_highlight_pass? buf, y, state
        buf.hlstacks[y] != state
    end
    def highlight_line buf, line, ypos
        require 'strscan'
        if !@aelexer_state_cache_per_buffer.has_key? buf
            @aelexer_state_cache_per_buffer[buf] = []
        end
        dbg(:dbg_highlight) { "<RubyHighlighter line=#{ypos}>" }
        next_color = nil
        hl_stack            = (ypos == 0) ? [] : buf.hlstacks[ypos - 1].dup    rescue [] # HACK
        current_class_stack = (ypos == 0) ? [] : buf.classstacks[ypos - 1].dup rescue [] # HACK dupl
        dbg(:dbg_highlight) { "-#- #{line} #{ypos} #{hl_stack.inspect} #{current_class_stack.inspect}" }
        backslash_continuation = ((hl_stack.last || HlElement.new).str == "\\")
        dbg(:dbg_highlight) { "(got a backslash continuation!)" } if backslash_continuation
        hl_stack.pop if backslash_continuation
        got_backslash = false
        x = 0
        tokens = []
        states_for_line = @aelexer_state_cache_per_buffer[buf][ypos - 1]
        states_for_line = states_for_line.nil? ? [] : states_for_line.dup
        @lexer.set_states states_for_line 
        @lexer.set_result []
        @lexer.lex_line(line.to_s)
        dbg(:dbg_highlight) { "aelexer result :: #{@lexer.result.inspect}" }
        is_proc_params, could_be_proc_params = false, false
        @lexer.result.each_with_index {
            |(str,style), idx|
            style_col = nil
            case style
            when :heredoc, :string, :literal, :number, :regexp
               style_col = Curses::COLOR_MAGENTA
            when :string1, :regexp1, :literal1, :literal_definer, :literal_ending
               style_col = Curses::COLOR_RED
            when :mcomment, :comment
               style_col = Curses::COLOR_CYAN
            when :gvar, :symbol
               style_col = Curses::COLOR_CYAN
            when :space, :tab
               ;
            when :punct
               if str == "|"
                  style_col = Curses::COLOR_CYAN
                  is_proc_params = !is_proc_params
                  could_be_proc_params = false
               end
            when :ident, :keyword, :dot
               could_be_proc_params = false
            else
               raise "#{style} not overriden!" if $test_case
            end
            if !style_col.nil?
               token = HlElement.new(str, x)
               tokens << token
               yield style_col, true, str if block_given?
               x += str.length
               next
            end
            matched = str
            full_line = [backslash_continuation ? buf.lines[ypos-1].sub(/\\\s*$/, "") : nil, line].compact.join
            dbg(:dbg_highlight) { matched.inspect }
            word = matched
            token = HlElement.new(word, x)
            tokens << token
            was_end = false
            just_popped = nil
            if RUBY_STRING_BLOCKS.detect { |b, e| word == e and hl_stack.collect{|t|t.str}.include? b }
                just_popped = hl_stack.pop.str
            elsif (word == "end" or word == "}" or word == ")") and !hl_stack.empty?
                word = hl_stack.pop.str
                if RUBY_STRUCTURE_START_KEYWORDS.include? word
                    dbg(:class_stack) { "GOT POP STATE" }
                    current_class_stack.pop
                end
                was_end = true
            end
            color = nil
            RUBY_STRING_BLOCKS.keys.each {
               |term|
               word = term if hl_stack.collect{|t|t.str}.include? term or just_popped == term
            }
            RUBY_STRING_BLOCKS.keys.each {
               |term|
               hl_stack.push token if word == term and ! (hl_stack.collect{|t|t.str}.include? term) and just_popped != term
            }
            got_backslash = false
            case word
            when /\\/
                got_backslash = true
            when *RUBY_BLAH
                t_next_color = Curses::COLOR_CYAN  if word =~ /def/
                t_next_color = Curses::COLOR_GREEN if word =~ /class|module/
                blub = RUBY_STRUCTURE_START_KEYWORDS.include? word
                if !was_end and blub
                    full_line =~ /#{word}\s+([a-zA-Z_.]+)/
                    current_class_stack.push $1
                    dbg(:class_stack) { "GOT PUSH STATE - #{$1.inspect}" }
                end
                color = Curses::COLOR_BLUE
                no_push = !blub
                hl_stack.push token unless no_push || was_end
                tokens.pop if no_push
            when /^(nil|true|false|self)$/
                color = Curses::COLOR_MAGENTA
            when /^(and|or|not|proc)$/
                color = Curses::COLOR_YELLOW
            when *(RUBY_DO_NOT_PUSH_KEYWORDS + RUBY_BLOCK_START_KEYWORDS)
                color = Curses::COLOR_YELLOW
                no_push = RUBY_DO_NOT_PUSH_KEYWORDS.include? word
                dbg(:dbg_highlight) { "no_push :: #{no_push} word: #{word}" }
                no_push = true if (full_line =~ /[^\s].*?\b#{Regexp.quote matched}\b.*?[^\s]/)
                dbg(:dbg_highlight) { "no_push :: #{no_push} full_line: #{full_line}" }
                if matched == "do"
                   t = @lexer.result[0...idx].find_all { |(tok_str, tok_style)| 
                                                         !([:tab, :space].include? tok_style) }
                   no_push = false if t.first[1] != :keyword
                end
                hl_stack.push token unless no_push || was_end
                tokens.pop if no_push
                could_be_proc_params = true if word == 'do'
            when '{', '('
                color = Curses::COLOR_BLUE if word == '{'
                color = Curses::COLOR_RED  if word == '('
                hl_stack.push token unless was_end
                could_be_proc_params = true if word == '{'
            when '}', ')'
                color = Curses::COLOR_RED  if word == ')'
                color = Curses::COLOR_BLUE if word == '}'
            when /^((@|@@|\$|:)[a-zA-Z_]+)$/, /^[A-Z_]+$/, /^([A-Z][a-z]+)+$/, /^\|.*?\|$/
                color = Curses::COLOR_CYAN
            end
            if is_proc_params
                color = Curses::COLOR_CYAN
            end
            if color.nil? || !next_color.nil?
                color = next_color.nil? ? Curses::COLOR_WHITE : next_color
                next_color = nil      unless word =~ /\s+/
            end
            next_color = t_next_color unless word =~ /\s+/
            bold = (color != Curses::COLOR_WHITE)
            yield color, bold, matched if block_given?
            dbg(:dbg_highlight) { "STATE : #{hl_stack.inspect}" }
            x += matched.length
        }
        hl_stack.push HlElement.new("\\", -1) if got_backslash
        buf.tokens[ypos]      = tokens
        buf.classstacks[ypos] = current_class_stack
        buf.hlstacks[ypos]    = hl_stack
        @aelexer_state_cache_per_buffer[buf][ypos] = @lexer.states
        dbg(:dbg_highlight) { "</RubyHighlighter>" }
        return hl_stack
    end
end

end
