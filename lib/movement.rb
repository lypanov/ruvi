module Ruvi

class EditorApp
    
    ###################
    # SCROLLING STUFF #
    ###################

    # test - scroll up and down in large buffer, needs visual test really
    def scroll_up buffer
        b = (buffer.top > 0)
        if b
            buffer.need_to_scroll = -1 unless buffer.needs_redraw 
            invalidate_screen_line buffer, 0 unless buffer.needs_redraw
            buffer.y -= 1
            buffer.top -= 1
            buffer.needs_redraw = true if buffer.got_a_scroll_already
            buffer.got_a_scroll_already = true
        end
        return b
    end

    # test - scroll up and down in large buffer, needs visual test really
    def scroll_down buffer
        b = (buffer.top + screen_height <= buffer.lines.length)
        if b
            buffer.need_to_scroll = 1 unless buffer.needs_redraw 
            invalidate_screen_line buffer, screen_height - 1 unless buffer.needs_redraw
            buffer.y += 1
            buffer.top += 1
            buffer.needs_redraw = true if buffer.got_a_scroll_already
            buffer.got_a_scroll_already = true
        end
        return b
    end

    ##########################
    # CLEVER WORD SKIP STUFF #
    ##########################
    
    def next_word buffer, *options
        letter_after   = options.include? :letter_after
        rev            = options.include? :reverse
        space_flag     = options.include? :skip_space
        greedy         = options.include? :greedy
        sub_identifier = options.include? :sub_identifier
        line = buffer.lines[buffer.y].dup
        pos = rev ? (line.length-buffer.x+1) : buffer.x
        space = space_flag ? '\s*' : ''
        jump_over_re = nil
        if !rev
            jump_over_re =   (greedy ? '[^\s]*\s*'       \
                                     : '( (\s+)'         \
                                       +
                     (sub_identifier ? '| ([A-Z][a-z]+)' \
                                       '| ([a-zA-Z]+_?)' \
                                       '| ([A-Z]+)'      \
                                       '| ([\d]+)'       \
                                     : '| (\w+)'
                                    )  + 
                                       '| ([^\s\w])'     \
                                       '| (.)'           \
                                       ')'               \
                                       + space )
            # test - b
        else
            jump_over_re =   (greedy ? '\s*[^\s]*'       \
                                     : space             \
                                       + '( (\s+)'       \
                                       +
                     (sub_identifier ? '| ([a-z]+[A-Z])' \
                                       '| (_?[a-zA-Z]+)' \
                                       '| ([A-Z]+)'      \
                                       '| ([\d]+)'       \
                                     : '| (\w+)'
                                    )  + 
                                       '| ([^\s\w])'     \
                                       '| (.)'           \
                                       ')' )
        end
        sub = rev ? line[0..(buffer.x-1)].reverse : line[buffer.x..(line.length-1)]
        sub =~ /^(#{jump_over_re})/x
        return if $1.nil?
        len = $1.length
        len += (!rev ? -1 : 1) unless letter_after or rev
        x_diff = rev ? (-len) : len
        move_x buffer, x_diff, (buffer.x == (line.length - 1) || buffer.x == 0) ? true : false
    end
    
    #####################
    # WRAPPING MOVEMENT #
    #####################
    
    def move_x buffer, x_diff, allow_y_change = true
        return if buffer.lines.empty?
        # need to limit max buffer.y change to 1
        return if x_diff == 0
        if x_diff > 0
            left_on_this_line = buffer.lines[buffer.y].length - buffer.x
            # we don't want to wrap, so capability states that we decrease the possible by one
            wanted_and_capable_on_this_line = (left_on_this_line - 1).clamp_to(0, x_diff)
            if left_on_this_line == 1 # the wrap == 1
                return unless allow_y_change
                x_diff -= 1
                move_y buffer, 1
                buffer.x = 0
                move_x buffer, x_diff
            else
                x_diff -= wanted_and_capable_on_this_line
                buffer.x += wanted_and_capable_on_this_line
                # we always move to end, and then wrap if needed
            end
        else
            left_on_this_line = buffer.x
            # in this case left_on_this_line == 0 when we can wrap so no need to adjust
            wanted_and_capable_on_this_line = [x_diff.abs, left_on_this_line].min
            if left_on_this_line == 0 # the wrap is at position 0
                return unless allow_y_change
                x_diff += 1 # its a negative
                move_y buffer, -1
                buffer.x = buffer.last_char_on_line(buffer.y)
                move_x buffer, x_diff
            else
                x_diff += wanted_and_capable_on_this_line # its negative
                buffer.x -= wanted_and_capable_on_this_line
                # we always move to the start, and then wrap if needed
            end
        end
    end

    def scroll_to_bottom buffer
        while scroll_down(buffer); end
        buffer.y = buffer.last_line_num
        redraw buffer
    end

    def scroll_to_top buffer
        while scroll_up(buffer); end
        buffer.y = 0
        redraw buffer
    end

    def move_y buffer, y_diff
        return if buffer.lines.empty?
        new_doc_y = buffer.y + y_diff
        if new_doc_y < 0
            scroll_to_bottom buffer
        elsif new_doc_y > buffer.lines.length - 1
            scroll_to_top buffer
        elsif new_doc_y < buffer.top
            diff = buffer.y - new_doc_y
            diff.times { scroll_up(buffer) }
        elsif new_doc_y > (buffer.top + screen_height - 1)
            diff = new_doc_y - buffer.y
            diff.times { scroll_down(buffer) }
        else
            buffer.y = new_doc_y
        end
        if @end_char_mode
            # in insert mode in vim, last char is indicated visually...
            buffer.x = buffer.last_char_on_line(buffer.y)
            # buffer.x accessor resets the end_char_mod, so lets restore :)
            @end_char_mode = true
        else
            buffer.x = buffer.x.clamp_to 0, buffer.last_char_on_line(buffer.y)
        end
    end

 end
 end
