module Ruvi
   class EditorApp

    def setup_edit_bindings
        $blk_join_line_block = proc {
            |c|
            buffer = self.current_buffer
            if buffer.y == buffer.last_line_num
               # beep :)
               # fixme - needs test
            else
            get_indent_level(buffer.lines[buffer.y])
            DiffLogger::ModifyLineChange.new(buffer, buffer.y + 1) {
               line = buffer.lines[buffer.y + 1]
               line.slice! 0, get_indent_level(line)
               line[0,0] = " "
            }
            EditorApp.join_next_line_onto_this buffer, buffer.y
            end
        }

#OTHER
        $blk_macro_block = proc {
            |c|
            buffer = self.current_buffer
            if @doing_macro.nil?
                @mode_stack.push :get_letter
                @get_letter_pop_proc = proc {
                    |c|
                    @doing_macro = ""
                    @macro_letter = c
                }
            else
                raise "er. how the fuck else did u exit macro mode thingy???" if @doing_macro[-1] != ?q
                @doing_macro.slice!(-1)
                @macros[@macro_letter] = @doing_macro
                @doing_macro = nil
            end
        }

#OTHER
        $blk_play_macro_block = proc {
            |c|
            buffer = self.current_buffer
            @mode_stack.push :get_letter
            @get_letter_pop_proc = proc {
                |c|
                @macros[c].each_byte { |c| send_key c }
            }
        }

        $blk_repeat_previous_command_block = proc {
            |c|
            buffer = self.current_buffer
            if !@last_command.nil?
                status_bar_edit_line "executing #{@last_command}"
                was_nil_selection = @selection.nil?
                @selection = @selection_for_last_command if was_nil_selection
                cmd = @last_command
                cmd.each_byte { |key| send_key key }
                @last_command = cmd
                @selection = nil if was_nil_selection
            end
        }

#OTHER
        $blk_select_paste_buffer_block = proc {
            @mode_stack.push :get_letter
            @get_letter_pop_proc = proc {
                |c|
                @current_paste_buffer = c.chr
            }
        }

        $blk_undo_block = proc {
            |c|
            buffer = self.current_buffer
            buffer.dlog.undo
            redraw buffer
        }

        $blk_insert_block = proc {
            |c|
            buffer = self.current_buffer
            line = buffer.lines[buffer.y]
            buffer.move_to_x get_indent_level(line) if (c.chr == c.chr.upcase)
            @end_char_mode = true if line.empty?
            begin_insert_mode buffer
        }

        $blk_replace_block = proc {
            |c|
            buffer = self.current_buffer
            begin_insert_mode buffer
            @replace_mode = true
        }

        $blk_replace_letter_block = proc {
            |c|
            buffer = self.current_buffer
            begin_insert_mode buffer
            @replace_mode = true
            @replace_single_letter = true
        }

#OTHER
        $blk_enter_command_mode_block = proc {
            |c|
            buffer = self.current_buffer
            begin_insert_mode buffer
            @mode_stack = [:command]
            status_bar_edit_line ":"
        }

        $blk_vi_y_block = proc {
            |c|
            buffer = self.current_buffer
            handle_generic_command buffer, c
        }

#OTHER
        $blk_debug_buffer_block = proc {
            |c|
            buffer = self.current_buffer
            switch_to_buffer @debug_buffer
        }

#OTHER
        $blk_goto_classstack_or_buffer_block = proc {
            |c|
            buffer = self.current_buffer
            # buffer specific... some kind of subclass or so?
            line = buffer.lines[buffer.y]
            idx_s = nil
            if    line =~ /^\[:b([0-9]+?)\]/
                idx = $1.to_i # due to to_i sucking we need to never have 1 numbered buffers
                switch_to_buffer @buffers.detect { |b| b.bnum == idx }
                BufferListExtension.clear_extension_buffers self
            elsif line =~  /^\[:([0-9]+?)\]/
                line_no = $1.to_i
                tbuffer = buffer.old_buf
                tbuffer.x      = 0
                tbuffer.y      = line_no
                unclamped_top  = line_no - (screen_height / 2)
                tbuffer.top    = unclamped_top.clamp_to 0, tbuffer.last_line_num
                switch_to_buffer buffer.old_buf
                HierarchyListExtension.clear_extension_buffers self
            end
        }

#OTHER
        $blk_show_classstack_block = proc {
            |c|
            buffer = self.current_buffer
            ensure_buffer_highlighted buffer
            class_list = []
            done = []
            buffer.classstacks.each_with_index {
                |stack, idx| 
                next if stack.empty?
                str = stack.join "::"
                unless done.include? str
                    done << str
                    class_list << Struct.new(:y, :s).new(idx, str)
                end
            }
            cur_class_y = 0
            b = HierarchyListExtension.create_buffer self
            class_list.each_with_index {
                |c, idx| 
                b.lines << BufferLine.new("[:#{c.y}] #{c.s}")
                next_one = class_list.at(idx + 1)
                if (cur_class_y == 0) and (next_one.nil? \
                                        || next_one.y > buffer.y)
                    cur_class_y = idx
                end
            }
            b.y   = cur_class_y
            b.top = b.y
            switch_to_buffer b
        }

#OTHER
        $blk_show_buffer_list_block = proc {
            |c|
            buffer = self.current_buffer
            b = BufferListExtension.create_buffer self
            @buffers.each {
                |buffer|
                visible_idx = buffer.fake_buffer ? " " : buffer.bnum
                b.lines << BufferLine.new("[:b#{visible_idx}] - #{buffer.fname} (length: #{buffer.lines.length}) (x:#{buffer.x}, y:#{buffer.y})")
            }
            switch_to_buffer b
        }

        $blk_previous_buffer_block = proc {
            |c|
            buffer = self.current_buffer
            switch_to_buffer
        }

        $blk_other_buffer_block = proc {
            |c|
            @current_docview = @docview2
        }

        $blk_redraw_block = proc {
            |c|
            buffer = self.current_buffer
            redraw buffer
        }

        $blk_redo_block = proc {
            |c|
            buffer = self.current_buffer
            buffer.dlog.redo
            redraw buffer
        }

        $blk_paste_buffer_block = proc {
            |c|
            buffer = self.current_buffer
            myy = buffer.y
            after = !(c.chr.upcase == c.chr)
            done_something = false            
            diff = 0
            paste_buffer = pop_paste_buffer
            paste_buffer.lines.each_with_index {
                |lbuffer, idx| 
                if after and !done_something
                    if lbuffer.newline_at_start
                        myy += 1 
                        diff = +1
                    else # !newline_at_start
                        buffer.x += 1 if buffer.x < buffer.lines[myy].length 
                    end
                end
                if lbuffer.newline_at_start and lbuffer.newline_at_end
                    # add totally new line
                    DiffLogger::InsertLineAfterChange.new(buffer, myy) {
                        buffer.lines.insert_after myy, lbuffer.dup
                    }
                elsif !lbuffer.newline_at_start and !lbuffer.newline_at_end 
                    # add in place
                    DiffLogger::ModifyLineChange.new(buffer, myy) {
                        buffer.lines[myy][buffer.x, 0] = lbuffer.dup
                    }
                elsif lbuffer.newline_at_start and !lbuffer.newline_at_end 
                    # append to the start of the next line - equiv to new line, then join
                    DiffLogger::ModifyLineChange.new(buffer, myy+1) {
                        buffer.lines[myy+1][0, 0] = lbuffer.dup
                    }
                elsif !lbuffer.newline_at_start and lbuffer.newline_at_end 
                    # add in place and split rest of line onto next line
                    rest_of_line  = nil
                    DiffLogger::ModifyLineChange.new(buffer, myy) {
                        rest_of_line = buffer.lines[myy].slice!(buffer.x..-1)
                    }
                    DiffLogger::ModifyLineChange.new(buffer, myy) {
                        buffer.lines[myy][buffer.x, 0] = lbuffer.dup
                    }
                    DiffLogger::InsertLineAfterChange.new(buffer, myy) {
                        buffer.lines.insert_after myy, rest_of_line
                    }
                end
                done_something = true
                myy += 1
            }
            buffer.y += diff
            redraw buffer
        }

        $blk_generic_vi_c_d_block = proc {
            |c|
            buffer = self.current_buffer
            handle_generic_command buffer, c
        }

        $blk_modify_indent_block = proc {
            |c|
            buffer = self.current_buffer
            @command << c.chr
            got_selection = !@selection.nil?
            selc = nil
            if got_selection
                selc = @selection.right_way_up
            elsif @command == c.chr*2
                selc = Selection.new Point.new(0, buffer.y), Point.new(buffer.lines[buffer.y].length, buffer.y), :selc_lined
                @command = ""
            elsif @command.length > 2
                @command = ""
            end
            if !selc.nil?
                tab = (" " * config_get_sw)
                backwards = (c == ?<)
                EditorApp.each_lineslice_in_selection(buffer, selc) {
                    |hlls| 
                    DiffLogger::ModifyLineChange.new(buffer, hlls.y) {
                        line = buffer.lines[hlls.y]
                        if backwards
                            line.slice! 0, [get_indent_level(line), config_get_sw].min
                        else
                            line[0, 0] = tab
                        end
                    }
                    EditorApp.invalidate_buffer_line buffer, hlls.y
                }
            end
        }

        $blk_reindent_block = proc {
            |c|
            buffer = self.current_buffer
            @command << c.chr
            got_selection = !@selection.nil?
            selc = nil
            if got_selection
                @command = ""
                selc = @selection.right_way_up
            elsif @command == c.chr*2
                selc = Selection.new Point.new(0, buffer.y), Point.new(buffer.lines[buffer.y].length, buffer.y), :selc_lined
                @command = ""
            end
            EditorApp.each_lineslice_in_selection(buffer, selc) {
                |hlls| 
                y = hlls.y
                next if y == 0
                current_line = buffer.lines[y-1]
                indent_string = calculate_autoindent buffer, current_line, y-1, true
                DiffLogger::ModifyLineChange.new(buffer, y) {
                    line = buffer.lines[y]
                    line.slice! 0, get_indent_level(buffer.lines[y])
                    line[0, 0] = indent_string
                }
                EditorApp.invalidate_buffer_line buffer, y
            }
        }

        $blk_vi_insert_after_block = proc {
            |c|
            buffer = self.current_buffer
            upcase = (c.chr.upcase == c.chr)
            cur_line_len = buffer.lines[buffer.y].length
            buffer.move_to_x(upcase ? buffer.last_char_on_line(buffer.y) : [buffer.x + 1, cur_line_len].min)
            @end_char_mode = true if buffer.x == buffer.last_char_on_line(buffer.y)
            begin_insert_mode buffer
        }

        $blk_vi_insert_new_line_block = proc {
            |c|
            buffer = self.current_buffer
            upcase = (c.chr.upcase == c.chr)
            insert_line = upcase ? buffer.y : buffer.y + 1
            indent_string = calculate_autoindent buffer, "", insert_line - 1, false
            line = BufferLine.new(indent_string)
            DiffLogger::InsertLineAfterChange.new(buffer, insert_line) {
                buffer.lines.insert_after insert_line, line
            }
            buffer.move_to(indent_string.length, insert_line)
            @end_char_mode = true
            begin_insert_mode buffer
            redraw buffer
        }

#OTHER
        $blk_vi_escape_mode_block = proc {
            |c|
            buffer = self.current_buffer
            @selection = nil
            @command = ""
        }

        $blk_change_line_block = proc {
            |c|
            buffer = self.current_buffer
            buffer.move_to_x 0
            DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                buffer.lines[buffer.y].replace BufferLine.new("")
            }
            EditorApp.invalidate_buffer_line buffer, buffer.y
            @end_char_mode = true
            begin_insert_mode buffer
        }

        $blk_edit_or_delete_till_end_block = proc {
            |c|
            buffer = self.current_buffer
            cmd = c.chr.downcase
            is_c = (cmd == "c")
            selc = Selection.new Point.new(buffer.x, buffer.y), Point.new(buffer.last_char_on_line(buffer.y), buffer.y), :selc_normal
            EditorApp.manip_selection buffer, selc, :manip_cut, pop_paste_buffer
            @end_char_mode = true
            EditorApp.invalidate_buffer_line buffer, buffer.y
            begin_insert_mode(buffer) if is_c
        }

        $blk_change_letter_block = proc {
            |c|
            buffer = self.current_buffer
            selc = Selection.new Point.new(buffer.x, buffer.y), Point.new(buffer.x, buffer.y), :selc_normal
            EditorApp.manip_selection buffer, selc, :manip_cut, pop_paste_buffer
            if buffer.lines[buffer.y].empty?
                @end_char_mode = true
            else
            buffer.x -= 1 if buffer.x >= buffer.lines[buffer.y].length
            end
            EditorApp.invalidate_buffer_line buffer, buffer.y
            begin_insert_mode buffer
        }

        $blk_vi_delete_char_block = proc {
            |c|
            buffer = self.current_buffer
            got_selection = !@selection.nil?
            if got_selection
                EditorApp.manip_selection buffer, @selection, :manip_cut, pop_paste_buffer
                end_selection buffer
            elsif buffer.lines[buffer.y].length > 0
                upcase = (c.chr.upcase == c.chr)
                buffer.x -= 1 if upcase
                selc = Selection.new Point.new(buffer.x, buffer.y), Point.new(buffer.x, buffer.y), :selc_normal
                EditorApp.manip_selection buffer, selc, :manip_cut, pop_paste_buffer
                buffer.x -= 1 if buffer.x >= buffer.lines[buffer.y].length
                EditorApp.invalidate_buffer_line buffer, buffer.y
            end
        }

#OTHER
        $blk_scroll_up_line_no_cursor_move_block = proc {
            |c|
            buffer = self.current_buffer
            scroll_up(buffer)
        }

        $blk_scroll_down_line_no_cursor_move_block = proc {
            |c|
            buffer = self.current_buffer
            scroll_down(buffer)
        }

        $blk_page_down_move_cursor_half_page_block = proc {
            |c|
            buffer, moved = self.current_buffer, false
            (screen_height / 2).times {
                able_to_move = scroll_down(buffer)
                moved = true if able_to_move
                break if not able_to_move
            }
            redraw buffer if moved
        }

        $blk_page_down_move_cursor_block = proc {
            |c|
            buffer, moved = self.current_buffer, false
            screen_height.times {
                able_to_move = scroll_down(buffer)
                moved = true if able_to_move
                break if not able_to_move
            }
            redraw buffer if moved
        }

        $blk_page_up_move_cursor_half_page_block = proc {
            |c|
            buffer, moved = self.current_buffer, false
            (screen_height / 2).times {
                able_to_move = scroll_up(buffer)
                moved = true if able_to_move
                break if not able_to_move
            }
            redraw buffer if moved
        }

        $blk_page_up_move_down_cursor_block = proc {
            |c|
            buffer, moved = self.current_buffer, false
            screen_height.times {
                able_to_move = scroll_up(buffer)
                moved = true if able_to_move
                break if not able_to_move
            }
            redraw buffer if moved
        }

#OTHER
        $blk_insert_escape_block = proc {
            buffer = self.current_buffer
            begin_normal_mode buffer
            buffer.dlog.flush
            @end_char_mode = false
            @replace_mode = false
            @replace_single_letter = false
        }

        $blk_insert_backspace_block = proc {
            buffer = self.current_buffer
            if buffer.x == 0 and buffer.y == 0
                # ignore backspace on first char in buffer
            elsif buffer.x == 0 and (!@end_char_mode or  \
                                     (@end_char_mode and buffer.lines[buffer.y].empty?))
                # join current line onto previous line and move to old end of last line
                line_to_join = nil
                DiffLogger::RemoveLineChange.new(buffer, buffer.y) {
                    line_to_join = buffer.lines.delete_at(buffer.y)
                }
                buffer.y -= 1
                DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                    join_to = buffer.lines[buffer.y]
                    if line_to_join.length == 0
                        buffer.move_to_x join_to.length - 1
                        @end_char_mode = true
                    else
                        buffer.move_to_x join_to.length
                    end
                    join_to << line_to_join
                    redraw_from_and_including buffer, buffer.y
                }
            else
                raise "out_of_bounds error!" if buffer.out_of_bounds buffer.y, buffer.x
                current_line = buffer.lines[buffer.y]
                current_indent = get_indent_level current_line
                bx = buffer.ax
                len = (current_indent == bx ? config_get_sw : 1)
                len = len.clamp_to 0, bx
                DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                    buffer.lines[buffer.y].slice! bx - len, len
                }
                ecm = @end_char_mode
                buffer.move_to_x(limit_to_positive(buffer.x - len))
                @end_char_mode = ecm
                EditorApp.invalidate_buffer_line buffer, buffer.y
            end
        }

        $blk_insert_cr_key_block = proc {
            buffer = self.current_buffer
            current_line = buffer.lines[buffer.y]
            indent_string = calculate_autoindent buffer, current_line, buffer.y, true
            should_fixup_end_pair = (current_line[buffer.x - 1,2] == "{}") and (@settings[:autopair] == "true")
            if buffer.ax == current_line.length
                line = BufferLine.new(indent_string)
            else
                # split the rest of the current line onto the next line
                DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                    line = BufferLine.new(indent_string + current_line.slice!(buffer.x, current_line.length)).dup
                }
            end
            DiffLogger::InsertLineAfterChange.new(buffer, buffer.y+1) {
                buffer.lines.insert_after buffer.y+1, line 
            }
            if should_fixup_end_pair 
                indent_string = calculate_autoindent buffer, buffer.lines[buffer.y], buffer.y, false
                DiffLogger::InsertLineAfterChange.new(buffer, buffer.y+1) {
                    buffer.lines.insert_after buffer.y+1, indent_string
                }
            end
            buffer.y += 1
            if indent_string.length > buffer.last_char_on_line(buffer.y)
                buffer.move_to_x indent_string.length - 1
                @end_char_mode = true
            else
                buffer.move_to_x indent_string.length
            end
            if buffer.lines[buffer.y].empty?
                buffer.move_to_x 0
                @end_char_mode = true
            end
            redraw buffer
        }

#OTHER
        $blk_insert_end_key_block = proc {
            buffer = self.current_buffer
            buffer.move_to_x buffer.last_char_on_line(buffer.y)
            @end_char_mode = true
        }

#OTHER
        $blk_insert_home_key_block = proc {
            buffer = self.current_buffer
            buffer.move_to_x 0
        }

#OTHER
        $blk_insert_movement_block = proc {
            |c|
            buffer = self.current_buffer
            do_movement_key buffer, c, :insert_mode
        }

        # INSERT BINDINGS
        add_insert_binding("\e", &$blk_insert_escape_block)
        add_insert_binding("\b", &$blk_insert_backspace_block)
        add_insert_binding("\r", &$blk_insert_cr_key_block)

        add_curses_key_translators(Curses::KEY_END  => "\C-x\C-h$", Curses::KEY_HOME  => "\C-x\C-h0")
        add_insert_binding("\C-x\C-h$", &$blk_insert_end_key_block)
        add_insert_binding("\C-x\C-h0", &$blk_insert_home_key_block)

        add_curses_key_translators(Curses::KEY_UP   => "\C-x\C-hk", Curses::KEY_DOWN  => "\C-x\C-hj", 
                                   Curses::KEY_LEFT => "\C-x\C-hh", Curses::KEY_RIGHT => "\C-x\C-hl")
        add_insert_binding("\C-x\C-hh", "\C-x\C-hj", "\C-x\C-hk", "\C-x\C-hl", &$blk_insert_movement_block)

        # COMMAND BINDINGS
        add_command_binding("t", "T", "f", "F", &$blk_look_for_letter_block)
        add_command_binding("^", &$blk_goto_first_real_letter_on_line_block)
        add_command_binding("}", "{", &$blk_skip_block_block)
        add_command_binding("w", "W", "e", "E", "b", "B", "zh", "zl", &$blk_word_movement_block)
        add_command_binding("H", &$blk_goto_top_of_screen_block)
        add_command_binding("L", &$blk_goto_end_of_screen_block)
        add_command_binding("M", &$blk_goto_mid_screen_line_block)
        add_command_binding("g", &$blk_vi_g_block)
        add_command_binding("G", &$blk_vi_cap_g_block)
        add_command_binding("n", "N", &$blk_next_prev_search_block)
        add_command_binding("*", "#", &$blk_find_next_word_block)
        add_command_binding("%", &$blk_match_paren_block)
        add_command_binding("k", "j", "h", "l", "\C-x\C-hh", "\C-x\C-hj", "\C-x\C-hk", "\C-x\C-hl", &$blk_insert_mode_cursor_block)
        add_command_binding("$", "\C-x\C-h$", &$blk_end_block)
        add_command_binding("\C-x\C-h0", &$blk_home_block)
        add_command_binding("v", "V", "\C-V", &$blk_selection_block)
        add_command_binding("/", "?", &$blk_search_block)
        add_command_binding("J", &$blk_join_line_block )
        add_command_binding("q", &$blk_macro_block)
        add_command_binding("@", &$blk_play_macro_block)
        add_command_binding(".", &$blk_repeat_previous_command_block)
        add_command_binding("i", "I", &$blk_insert_block)
        add_command_binding("u", &$blk_undo_block)
        add_command_binding("\"", &$blk_select_paste_buffer_block)
        add_curses_key_translators(Curses::KEY_PPAGE => "\C-b", Curses::KEY_NPAGE => "\C-f")
        add_command_binding("\C-b", &$blk_page_up_move_down_cursor_block)
        add_command_binding("\C-f", &$blk_page_down_move_cursor_block)
        add_command_binding("\C-e", &$blk_scroll_down_line_no_cursor_move_block)
        add_command_binding("s", &$blk_change_letter_block)
        add_command_binding("D", "C", &$blk_edit_or_delete_till_end_block)
        add_command_binding("S", &$blk_change_line_block)
        add_command_binding("\e", &$blk_vi_escape_mode_block)
        add_command_binding("o", "O", &$blk_vi_insert_new_line_block)
        add_command_binding("a", "A", &$blk_vi_insert_after_block)
        add_command_binding("=", &$blk_reindent_block)
        add_command_binding("<", ">", &$blk_modify_indent_block)
        add_command_binding("c", "d", &$blk_generic_vi_c_d_block)
        add_command_binding("\C-r", &$blk_redo_block)
        add_command_binding("\C-l", &$blk_redraw_block)
        add_command_binding("\C-w\C-o", &$blk_previous_buffer_block)
        add_command_binding("\C-w\C-w", &$blk_other_buffer_block)
        add_command_binding("\C-s", &$blk_show_buffer_list_block)
        add_command_binding("\C-x\C-c", &$blk_show_classstack_block)
        # TODO - following is a "bit" of a hack...
        add_command_binding("\r", &$blk_goto_classstack_or_buffer_block)
        add_command_binding("\C-x\C-d", &$blk_debug_buffer_block)
        add_command_binding("\C-d", &$blk_page_up_move_cursor_half_page_block)
        add_command_binding("\C-u", &$blk_page_down_move_cursor_half_page_block)
        add_command_binding("y", &$blk_vi_y_block)
        add_command_binding("R", &$blk_replace_block)
        add_command_binding("r", &$blk_replace_letter_block)
        add_command_binding(":", &$blk_enter_command_mode_block)
        add_command_binding("p", "P", &$blk_paste_buffer_block)
        add_command_binding("x", "X", &$blk_vi_delete_char_block)
        add_command_binding("\C-y", &$blk_scroll_up_line_no_cursor_move_block)

    end

 end
 end
