module Ruvi
   class EditorApp

    def setup_bindings
       setup_movement_bindings
       setup_edit_bindings
    end

    def setup_movement_bindings
        $blk_look_for_letter_block = proc {
            |c|
            buffer = self.current_buffer
            @mode_stack.push :get_letter
            @get_letter_pop_proc = proc {
                |to_find|
                has_action = !@command.empty?
                selc_options = []
                selc_options << :restore if has_action
                selc = create_selection(buffer, :selc_normal, *selc_options) { 
                    upcase = (c.chr == c.chr.upcase)
                    letter_before = (c.chr.downcase == "t")
                    diff = letter_before ? 1 : 0
                    line = buffer.lines[buffer.y]
                    if upcase
                        # backwards search...
                        if buffer.x != 0
                            index = line.rindex(to_find, buffer.x-1)
                            buffer.move_to_x(index + diff) unless index.nil?
                        end
                    else
                        # forwards search
                        if buffer.x != line.length - 1
                            index = line.index(to_find, buffer.x+1)
                            buffer.move_to_x(index - diff) unless index.nil?
                        end
                    end
                }
                do_action buffer, selc
            }
        }

        $blk_goto_first_real_letter_on_line_block = proc {
            |c|
            buffer = self.current_buffer
            buffer.move_to_x get_indent_level(buffer.lines[buffer.y])
        }

        $blk_skip_block_block = proc {
            |c|
            buffer = self.current_buffer
            backwards = (c == ?{)
            oy = buffer.y
            while true
                move_y buffer, backwards ? -1 : +1
                break if buffer.lines[buffer.y] =~ /^\s*$/ \
                      or    (buffer.y != oy \
                        and ([buffer.last_line_num, 0].include? buffer.y))
            end
            if buffer.y == buffer.last_line_num and !backwards
               buffer.move_to_x buffer.last_char_on_line(buffer.last_line_num)
            else
               # used in the { at start of file case, and the default case
               buffer.move_to_x 0
            end
        }

        #: : attribution - vim help - motion.txt
        #    Special case: "cw" and "cW" are treated like "ce" and "cE" if the cursor is
        #    on a non-blank.  This is because "cw" is interpreted as change-word, and a
        #    word does not include the following white space.  {Vi: "cw" when on a blank
        #    followed by other blanks changes only the first blank; this is probably a
        #    bug, because "dw" deletes all the blanks}
        $blk_word_movement_block = proc {
            |c, context|
            options = [ ]
            case context.input
            when "zh"
                options << :sub_identifier
                c = ?b
            when "zl"
                options << :sub_identifier
                c = ?w
            end
            buffer = self.current_buffer
            cmd = c.chr.downcase
            if_e = (cmd == "e")
            if_b = (cmd == "b")
            is_upcase = (c.chr.upcase == c.chr)
            has_action = !@command.empty?
            on_blank = (buffer.lines[buffer.y][buffer.x] =~ /\s/)
            letterafter = (cmd == "w")
            letterafter = false if (cmd == "w" and @command == "c" and !on_blank)
            options << :letter_after if letterafter
            options << :skip_space   if letterafter or (if_b and !has_action)
            options << :reverse      if if_b
            options << :greedy       if is_upcase
            ox, oy = buffer.x, buffer.y
            selc = create_selection(buffer, :selc_normal) { 
                next_word(buffer, *options)
            }
            if has_action
                selc = selc.right_way_up
                make_selection_exclusive_given_current_position(buffer, selc) if (letterafter or (@command == "c" and context.input == "zl"))
            end
            buffer.x, buffer.y = ox, oy if has_action
            should_make_exclusive = (if_b and has_action)
            make_selection_exclusive_given_current_position(buffer, selc) if should_make_exclusive
            do_action buffer, selc
        }

        $blk_goto_top_of_screen_block = proc {
            |c|
            buffer = self.current_buffer
            buffer.move_to_y buffer.top
        }

        $blk_goto_end_of_screen_block = proc {
            |c|
            buffer = self.current_buffer
            y = buffer.top + screen_height - 1
            y = [y, buffer.lines.length - 1].min
            buffer.move_to_y y
        }

        $blk_goto_mid_screen_line_block = proc {
            |c|
            buffer = self.current_buffer
            y = buffer.top + ([screen_height, buffer.last_line_num].min / 2)
            buffer.move_to_y y
        }

        $blk_vi_g_block = proc {
            |c|
            buffer = self.current_buffer
            @command << c.chr
            if @command == "gg"
                if @number =~ /[0-9]+/
                    buffer.move_to_y(@number.to_i - 1)
                    redraw buffer
                    @number = nil
                else
                    scroll_to_top buffer
                end
                @command = ""
            end
        }

        $blk_vi_cap_g_block = proc {
            |c|
            buffer = self.current_buffer
            if @number =~ /[0-9]+/
                buffer.move_to_y(@number.to_i - 1)
                redraw buffer
                @number = nil
            else
                selc = create_selection(buffer, :selc_lined) { 
                    scroll_to_bottom buffer 
                }
                do_action buffer, selc
            end
        }

        $blk_next_prev_search_block = proc {
            |c|
            buffer = self.current_buffer
            @search = SearchContext.new
            @search.history_pos = 0
            @search.reverse = (c.chr.upcase == c.chr)
            do_search(buffer, @search.reverse ? Curses::KEY_CTRL_P : Curses::KEY_CTRL_N)
            if !hl_selection.nil?
                buffer.move_to @hl_selection.s.x, @hl_selection.s.y
            end
            @search = nil
        }

        $blk_find_next_word_block = proc {
            |c|
            buffer = self.current_buffer
            @search = SearchContext.new
            @search.history_pos = 0
            @search.reverse = (c == ?#)
            word_range = get_word_under_cursor buffer
            word = buffer.lines[buffer.y].slice(word_range)
            status_bar_edit_line "* matched: #{word}"
            @search.already_performed = false
            do_search(buffer, Curses::KEY_CTRL_N, word) # see above
            buffer.move_to @hl_selection.s.x, @hl_selection.s.y
            @search = nil
        }

        $blk_match_paren_block = proc {
            |c|
            buffer = self.current_buffer
            # make movements work, e.g d% -> delete between ()s
            buffer.ensure_line_highlight buffer.y
            row = buffer.tokens[buffer.y]
            token = row.find { 
                        |tok| 
                        (tok == row.last) || (row[row.index(tok) + 1].x > buffer.x)
                    }
            matches_hash = buffer.highlighter.matches_hash
            inv_matches_hash = {}
            matches_hash.values.sort.uniq.each {
                |val| 
                inv_matches_hash[val] = matches_hash.collect { 
                                    |dom, rng| 
                                    rng == val ? dom : nil
                                }.compact
            }
            looking_backwards = matches_hash.values.include? token.str
            matches_hash_values, matches_hash_keys = matches_hash.values, matches_hash.keys
            we_want_a = looking_backwards ? inv_matches_hash[token.str] : [matches_hash[token.str]]
            level = 0
            val = looking_backwards ? -1 : 1
            token_itr(buffer, token, buffer.y, !looking_backwards) {
                |y, tok|
                level += val if matches_hash_values.include? tok.str
                if we_want_a.include?(tok.str) and level == 0
                    buffer.move_to tok.x, y
                    break
                end
                level -= val if matches_hash_keys.include? tok.str
            }
        }

        $blk_insert_mode_cursor_block = proc {
            |c|
            buffer = self.current_buffer
            by_line = [?j, ?k].include?(c)
            selc = create_selection(buffer, by_line ? :selc_lined : :selc_normal) { 
                do_movement_key buffer, c 
            }
            make_selection_exclusive_given_current_position(buffer, selc) unless by_line
            do_action buffer, selc
        }

        $blk_end_block = proc {
            |c|
            buffer = self.current_buffer
            has_action = !@command.empty?
            selc = create_selection(buffer, :selc_normal) { 
                buffer.move_to_x buffer.last_char_on_line(buffer.y)
                @end_char_mode = true unless has_action
            }
            make_selection_exclusive_given_current_position(buffer, selc) unless has_action
            do_action buffer, selc
        }

        $blk_home_block = proc {
            |c|
            buffer = self.current_buffer
            buffer.move_to_x 0
        }

        $blk_search_block = proc {
            |c|
            buffer = self.current_buffer
            @mode_stack.push :search
            @search = SearchContext.new
            @search.history_pos = 0
            @search.already_performed = false
            @search.reverse = (c == ??)
            @search.got_no_key = true
            status_bar_edit_line "enter search term: "
        }

        $blk_selection_block = proc {
            |c|
            buffer = self.current_buffer
            if !@selection.nil?
                @selection = nil
            else
                @selection = Selection.new
                @selection.mode = (c == ?\C-v) ? :selc_boxed : ((c == ?v) ? :selc_normal : :selc_lined)
                if    @selection.mode == :selc_normal || @selection.mode == :selc_boxed
                    @selection.s = Point.new(buffer.x, buffer.y)
                elsif @selection.mode == :selc_lined
                    @selection.s = Point.new(0, buffer.y)
                end
            end
        }
    end


 end
 end
