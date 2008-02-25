
module Ruvi
   class EditorApp

    def do_search buffer, c, word = nil
        forced_next = (c == Curses::KEY_CTRL_N || c == Curses::KEY_CTRL_P)
        @search.reverse = (c == Curses::KEY_CTRL_P) if forced_next
        if !@search.already_performed
            @case_sensitive = false
            @search.history_pos = @search_history.length
            if !word.nil?
                @search_history << word.dup
            elsif forced_next
                @search.history_pos -=  1
            else
                @search_history << ""
            end
            @search.string = @search_history.last # rename
        end
        case c
        when Curses::KEY_CTRL_I
            @case_sensitive = !@case_sensitive 
        when Curses::KEY_UP
            @search.history_pos -= 1 if @search.history_pos > 0
            @search.string = @search_history[@search.history_pos].dup
        when Curses::KEY_DOWN
            @search.history_pos += 1 if @search.history_pos < (@search_history.length - 1)
            @search.string = @search_history[@search.history_pos].dup
        when ESC_KEY, CR_KEY
            if c == CR_KEY and !@hl_selection.nil?
                buffer.move_to @hl_selection.s.x, @hl_selection.s.y
            end
            @hl_selection = nil
            @search.history_pos = @search_history.length - 1
            @search.already_performed = false
            if @search.got_no_key
                @search.history_pos = @search_history.length - 2
                @search.string = @search_history[@search.history_pos]
                @search_history.pop
                perform_search buffer, true
                buffer.move_to @hl_selection.s.x, @hl_selection.s.y
            end
            @mode_stack.pop
            @search = nil
            return
        when *BACKSPACE_KEYS
            @search.string.slice!(-1)
        when Curses::KEY_CTRL_N, Curses::KEY_CTRL_P
            ;
        else
            if c > ASCII_UPPER
                status_bar_edit_line "unhandled non ascii entry in do_search: #{c}"
            else
                @search.string << c.chr
                @search.got_no_key = false
            end
        end
        perform_search buffer, forced_next
    end
    
    def find_match_in_line re, line, myx, go_backwards, forced_next
        line_to_compare = line.dup
        start_pos, end_pos = nil, nil
        if !go_backwards
            skiplen = myx
            skiplen += 1 if forced_next
            line_to_compare.slice! 0, skiplen
            matches = (line_to_compare =~ re)
            matches = false if $1.nil? or $2.nil?
            start_pos, end_pos = ($1.length) + skiplen, ($1.length + $2.length - 1) + skiplen if matches
        else
            # chop off end - the bit after myx
            skiplen = myx
            line_to_compare.slice! skiplen...line_to_compare.length
            x = 0
            # scan all matches until the last match of the leftover string
            line_to_compare.scan(re) { 
                matches   = true 
                start_pos = x + $1.length
                end_pos   = start_pos + $2.length - 1
                x += ($1.length + $2.length)
            }
        end
        return matches, start_pos, end_pos
    end

    def status_bar_edit_line status, pos = -1
        @status_bar.text = status
        @status_bar.cursor.x, @status_bar.cursor.y = ((pos == -1) ? status.length : pos), 0
    end
        
    def perform_search buffer, forced_next
        @search.already_performed = true
        re = nil
        begin
            re = @case_sensitive ? /(.*?)(#{@search.string})/ : /(.*?)(#{@search.string})/i
        rescue RegexpError
            status_bar_edit_line ":( - #{@search.string}"
            return
        end
        cur_x, cur_y = buffer.x, buffer.y
        last_match_y = buffer.y
        moved, matches, search_wrapped = false, false, false
        dbg(:search) { "started! with search == #{@search.string}" }
        while true
            matches, start_pos, end_pos = find_match_in_line re, buffer.lines[cur_y], cur_x, @search.reverse, (forced_next and cur_y == buffer.y)
            last_match_y = cur_y if matches
            dbg(:search) { "B: #{start_pos.inspect} - #{end_pos.inspect}" }
            if  matches && !moved && ( (!@search.reverse && start_pos > cur_x) \
                                     || (@search.reverse && cur_x > start_pos) )
                moved = true
                cur_x = start_pos
            end
            if search_wrapped and moved and !matches && (cur_y == last_match_y)
                status_bar_edit_line "sorry, unable to find #{@search.string}"
                break
            end
            forced_next_but_unmoved = forced_next && !moved
            if matches and !forced_next_but_unmoved
                status_bar_edit_line ":) - #{@search.string}"
                break
            end
            cur_y += (@search.reverse ? -1 : +1)
            cur_x = @search.reverse ? buffer.lines[cur_y].length : 0
            if cur_y > (buffer.lines.length-1) or cur_y < 0
                status_bar_edit_line "wrapped!"
                search_wrapped = true 
            end
            cur_y = cur_y % buffer.lines.length
            moved = true
        end
        @hl_selection = matches ? Selection.new(Point.new(start_pos, cur_y),
                                                Point.new(end_pos,   cur_y), 
                                                :selc_normal) \
                                : nil
        redraw buffer
    end
    
 end
 end
