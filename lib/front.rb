module Ruvi

class EditorApp

    def get_binding_hash_key_pair initial_options, keys
        if keys.is_a? String
            last_char = keys.slice!(-1)
            options = initial_options
            keys.each_byte {
                |b|
                options[b] ||= {}
                options = options[b]
            }
            return options, last_char
        else
            return initial_options, keys
        end
    end

    def add_binding initial_options, *keys_a, &block
        keys_a.each {
            |keys|
            hash, key = get_binding_hash_key_pair initial_options, keys
            hash[key] = block
        }
    end

    def delete_binding initial_options, key
        hash, key = get_binding_hash_key_pair initial_options, key
        hash.delete key # returns also
    end

    def delete_command_binding key;        delete_binding @stored_command_bindings, key;        end
    def delete_insert_binding key;         delete_binding @stored_insert_bindings, key;         end
    def add_command_binding *keys, &block; add_binding @stored_command_bindings, *keys, &block; end
    def add_insert_binding *keys, &block;  add_binding @stored_insert_bindings, *keys, &block;  end
    def normalize_cursor_key c
        case c
        when Curses::KEY_RIGHT
            return ?l
        when Curses::KEY_UP
            return ?k
        when Curses::KEY_DOWN
            return ?j
        when Curses::KEY_LEFT
            return ?h
        end
        return c
    end

    def do_movement_key buffer, c, *options
        c = normalize_cursor_key c
        insert_mode = options.include? :insert_mode
        raise "ummm a @command number when in insert_mode are u insane???" if insert_mode and !@command.empty?
        if insert_mode and [?h, ?l].include? c
            eol_x = buffer.last_char_on_line(buffer.y)
            if buffer.x == eol_x and ( (@end_char_mode and c == ?h) or (!@end_char_mode and c == ?l) )
                @end_char_mode = !@end_char_mode
                return
            elsif buffer.x == 0  and c == ?h
                move_x buffer, -1
                @end_char_mode = !@end_char_mode
                return
            end
        end
        (@number || "1").to_i.times { 
            case c
            when ?k
                move_y buffer, -1
            when ?j
                move_y buffer, +1
            when ?h
                move_x buffer, -1
            when ?l
                move_x buffer, +1
            end
            @number = nil
        }
    end

    def begin_insert_mode buffer
        buffer.dlog.partial_flush_mode = true
        @mode_stack = [:insert]
        @da_command = ""
    end

    def begin_normal_mode buffer
        @last_command = @da_command
        buffer.dlog.partial_flush_mode = false
        buffer.dlog.flush
        @mode_stack = [:normal]
    end

    def create_selection buffer, type, *options, &block
        selc = Selection.new
        selc.mode = type
        selc.s = Point.new(type == :selc_lined ? 0 : buffer.x, buffer.y)
        block.call
        selc.e = Point.new(type == :selc_lined ? buffer.lines[buffer.y].length : buffer.x, buffer.y)
        if options.include? :restore
            buffer.move_to selc.s.x, selc.s.y
        end
        selc
    end

    def do_action buffer, selc
        case @command
        when "c", "d", "y"
            is_y = (@command == "y")
            is_c = (@command == "c")
            EditorApp.manip_selection buffer, selc, is_y ? :manip_copy : :manip_cut, pop_paste_buffer
            redraw buffer # - optimize!!!
            # EditorApp.invalidate_buffer_line buffer, buffer.y unless is_y
            @end_char_mode = true if selc.s.x == buffer.lines[buffer.y].length
            begin_insert_mode(buffer) if is_c 
            @command = ""
        end
    end 

    def handle_generic_command buffer, c
        got_selection = !@selection.nil?
        if got_selection
            @command = c.chr
            do_action buffer, @selection
            @command = ""
            end_selection buffer
        else
            @command << c.chr
            if @command == (c.chr * 2)
                selc = Selection.new Point.new(0, buffer.y), Point.new(buffer.lines[buffer.y].length, buffer.y), :selc_lined
                @command = c.chr
                do_action buffer, selc
                @command = ""
            end
        end
    end

    def do_command buffer, c
        number_char = nil
        char_string = (c > 256) ? @curses_key_translators[c] : c.chr
        @current_command_binding_state = @stored_command_bindings if @current_command_binding_state.nil?
        if (c > 256) or !@current_command_binding_state[c].nil?
            if @command_context.nil?
                @command_context = Struct.new(:input).new
                @command_context.input = ""
            end
            char_string.each_byte {
              |c|
              options = @current_command_binding_state[c]
              if options.is_a? Hash
                  @current_command_binding_state = options
                  @command_context.input << c.chr
              else
                  @command_context.input << c.chr
                  case options.arity
                  when 2
                      options.call c, @command_context
                  else
                      options.call c
                  end
                  @current_command_binding_state = nil
                  @command_context = nil
              end
            }
        else
            @command_context = nil
            @current_command_binding_state = nil
            case c
            when ?0..?9
                number_char = c
            else
                raise "[unknown key `#{Curses.keyname(c)}'=#{c}]" if $test_case
                status_bar_edit_line "[unknown key `#{Curses.keyname(c)}'=#{c}] "
            end
            # what a freaking haccckk :(
            if number_char.nil?
                unless @number.nil? or !@command.nil?
                    @number = nil
                    status_bar_edit_line "number ended..."
                end
            else
                if @number.nil? and number_char == ?0
                    buffer.move_to_x 0
                else
                    @number = "" if @number.nil?
                    @number << number_char.chr
                end
            end
        end
        if    !@selection.nil? and (@selection.mode == :selc_normal || @selection.mode == :selc_boxed)
            @selection.e = Point.new(buffer.x, buffer.y)
        elsif !@selection.nil? and @selection.mode == :selc_lined
            @selection.e = Point.new(buffer.lines[buffer.y].length, buffer.y)
        end
        @da_command << c.chr unless @mode_stack.last == :command or !@changed or c > 255
        if @command.empty? and @mode_stack.last == :normal and !@da_command.empty? and @changed
            @changed = false
            @last_command = @da_command
            @da_command = ""
        end
        buffer.dlog.flush
        update_selection buffer
        @status_bar.invalidate
    end

    def add_curses_key_translators *params
        hash = *params
        @curses_key_translators = @curses_key_translators.merge hash
    end

    def do_letter buffer, c
        @current_insert_binding_state = @stored_insert_bindings if @current_insert_binding_state.nil?
        c = 8 if BACKSPACE_KEYS.include? c
        char_string = (c > 256) ? @curses_key_translators[c] : c.chr
        if (c > 256) or !@current_insert_binding_state[c].nil?
            char_string.each_byte {
                |c|
                options = @current_insert_binding_state[c]
                if options.is_a? Hash
                    @current_insert_binding_state = options
                else
                    options.call c
                    @current_insert_binding_state = nil
                end
            }
        else
            @current_insert_binding_state = nil
            if c > ASCII_UPPER
                status_bar_edit_line "unhandled non ascii entry in do_letter: #{c}"
            else
                if !@settings[:tw].nil? and buffer.x > config_get_tw
                    current_line = buffer.lines[buffer.y]
                    x_was = buffer.x
                    ecm = @end_char_mode
                    next_word(buffer, :skip_space, :letter_after, :reverse, :greedy) if buffer.x > 0
                    if buffer.x == 0
                        buffer.x = x_was
                    else
                        indent_string = calculate_autoindent buffer, current_line, buffer.y, true
                        line = nil
                        DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                            line = BufferLine.new(indent_string + current_line.slice!(buffer.x..-1)).dup
                            current_line.gsub!(/\s*$/, '')
                        }
                        DiffLogger::InsertLineAfterChange.new(buffer, buffer.y+1) {
                            buffer.lines.insert_after buffer.y+1, line 
                        }
                        buffer.y += 1
                        buffer.move_to_x line.length
                        @end_char_mode = ecm
                    end
                end
                line = buffer.lines[buffer.y]
                ch = (c == 9) ? (" " * config_get_sw) : c.chr
                if !@end_char_mode and buffer.out_of_bounds buffer.y, buffer.x
                    raise "Out of bounds while inserting character in do_letter!" if $test_case
                    status_bar_edit_line "Can't insert character, cursor at invalid position on line!!!"
                    return
                end
                DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                    if @end_char_mode
                        # how to prevent replace_mode in this code path?
                        line << ch
                        buffer.move_to_x limit_to_positive(line.length - 1)
                        @end_char_mode = true
                    else
                        line[buffer.x, @replace_mode ? 1 : 0] = ch
                        buffer.move_to_x(buffer.x + ch.length)
                    end
                }
                if @settings[:autopair] == "true"
                 catch(:done) {
                    end_pair = nil
                    case c
                    when ?\ 
                        end_pair = " " if @last_inserted_char == ?{
                    when ?{ 
                        end_pair = "}"
                    end
                    if !end_pair.nil?
                        DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                            if @end_char_mode
                                line << end_pair
                                buffer.x += 1
                                @end_char_mode = false
                            else
                                line[buffer.x, 0] = end_pair
                            end
                        }
                    end
                 }
                end
                EditorApp.invalidate_buffer_line buffer, buffer.y
            end
            if @replace_single_letter
                buffer.dlog.flush
                begin_normal_mode buffer
                @replace_mode = false
                @replace_single_letter = false
                buffer.x -= 1
            end
        end
        @last_inserted_char = c
        @da_command << c.chr unless @mode_stack.last == :normal or c > 255
        buffer.dlog.flush
        @status_bar.invalidate
    end

    def setup_cmd cmd_string, re, &block
        possibles = []
        cmd_string.split(",").each {
            |word| 
            word << "'" if word.index('').nil?
            possibles += [word.sub(/'.*$/,""), word.sub(/'/, "")]
        }
        # @commands should be used in a shortest first fashion ... TODO
        possibles.sort.uniq.each {
            |possible|
            @commands[possible] = block
        }
        @cmds[re] = block
    end

    def setup_cmd_override re, &block
        @cmd_overrides[re] = block
    end

    CommandContext = Struct.new :cmd_line, :re, :buffer

    def cmd_execute buffer, cmd_line
        @cmd_overrides.each_pair {
            |re, block|
            if cmd_line =~ re
                ctx = CommandContext.new cmd_line, re, buffer
                block.call ctx
                return
            end
        }
        @cmds.each_pair {
            |re, block|
            if cmd_line =~ re
                ctx = CommandContext.new cmd_line, re, buffer
                block.call ctx
                return
            end
        }
        status_bar_edit_line "Unknown command: #{cmd_line}"
    end
    

    def get_cmd_line
        # used by testcases.rb
        @cmd_line
    end

    def find_prefix completions
        prefix = completions.first.dup
        completions.slice(1..-1).each {
            |str|
            idx = 0
            prefix.each_byte {
                |byte|
                if str.length < idx or str[idx] != byte
                    prefix = str.slice(0,idx)
                    break
                end
                idx += 1
            }
        }
        prefix
    end

    def do_cmd_mode c, current_string, &block
        possible_completions_string = ""
        had_completions = (@status_bar.text =~ /:.*\(.*\)/)
        case c
        when CR_KEY, ESC_KEY
            if c == CR_KEY
                block.call true
            else
                status_bar_edit_line "Command mode cancelled."
                block.call false
            end
            return
        when 9
            completions, to_cut, total_set, to_complete, to_skip_when_showing_options = nil, nil, nil, nil, nil
            if (current_string =~ /\s([^ \t]*)$/) 
                # attempt filename completion
                to_complete = $1
                dir = File.dirname(to_complete)
                completions = Dir[to_complete + "*"]
                to_cut = to_complete.length
                parent_dir = (to_complete =~ %r{/$}) ? to_complete : (File.dirname(to_complete) + "/")
                total_set = Dir[parent_dir + "*"]
                to_skip_when_showing_options = parent_dir.length
            else
                # do command completion
                completions = []
                @commands.each_key {
                    |key|
                    completions << key if key.index(current_string) == 0 or current_string.empty?
                }
                to_cut = current_string.length
                total_set = @commands.keys
                to_complete = current_string
                to_skip_when_showing_options = 0
            end
            completions = completions.sort_by { |b| b.length }
            if completions.length > 0
                prefix = find_prefix completions
                cmd_prefix = current_string[0, current_string.length - to_cut]
                if !prefix.empty? and (cmd_prefix + prefix) != current_string
                    possible_completions_string = " (#{completions.sort.join ","})"
                    current_string.replace cmd_prefix + prefix
                else
                    new_string = completions.sort.first.dup
                    if new_string == to_complete and had_completions
                        idx = total_set.sort.index(new_string) || 0 # default to the first item
                        to_complete = total_set.sort[(idx + 1) % total_set.length]
                        current_string.replace cmd_prefix + to_complete
                    else
                        current_string.replace cmd_prefix + new_string
                        to_complete = new_string
                    end
                    sorted_total_set = total_set.sort
                    selected = to_complete
                    current_idx = sorted_total_set.index selected
                    if current_idx.nil?
                        selected = completions.first
                        current_idx = sorted_total_set.index selected
                    end
                    my_subset = nil
                    unless current_idx.nil?
                        top = limit_to_positive(sorted_total_set.length - 1)
                        start_idx = (current_idx - 2).clamp_to(0, top)
                        end_idx =   (current_idx + 2).clamp_to(0, top)
                        my_subset = sorted_total_set.slice(start_idx..end_idx)
                        my_subset.unshift nil if (start_idx != 0)
                        my_subset.push    nil if (end_idx != top)
                    else
                        my_subset = sorted_total_set
                    end
                    options = my_subset.map { 
                        |s| 
                        t = s.slice(to_skip_when_showing_options..-1) rescue ""
                        (s == nil) ? "..." : ( (s == selected) ? "[#{t}]" : t )
                    }.join(",")
                    possible_completions_string = " (#{options})"
                end
                if !had_completions and completions.length == 1
                    possible_completions_string = ""
                end
            end
        when *BACKSPACE_KEYS
            if current_string.length > 0
                current_string.slice!(-1) 
            else
                status_bar_edit_line "Command mode cancelled."
                block.call false
                return
            end
        else
            if c > ASCII_UPPER
                status_bar_edit_line "unhandled non ascii entry in do_cmd_mode: #{c}"
            else
                current_string << c.chr
            end
        end
        status_bar_edit_line ":#{current_string}#{possible_completions_string}", current_string.length + 1
    end

    def send_key c
        dbg(nil) { "key press: #{(c == 27) ? "<esc>" : (c > 256 ? Curses.keyname(c) : c.chr)}" } unless $test_case
        $action_replay_log.keys_pressed << c unless $replaying
        update_focus
        @doing_macro << c.chr unless @doing_macro.nil?
        case @mode_stack.last
        when :search
            do_search @current_buffer, c
        when :normal
            do_command @current_buffer, c
        when :get_letter
            @mode_stack.pop
            @get_letter_pop_proc.call c
        when :command
            do_cmd_mode(c, @cmd_line) {
               |ok|
               cmd_execute @current_buffer, @cmd_line if ok
               @mode_stack = [:normal]
               @cmd_line = ""
            }
        when :insert
            do_letter @current_buffer, c
        end
        update_focus
    end

    def update_focus
        case @mode_stack.last
        when :search
            @focus = @status_bar
        when :normal, :insert, :get_letter
            @focus = current_docview
        when :command
            @focus = @status_bar
        when 
            @focus = current_docview
        end
    end
    
end

end
