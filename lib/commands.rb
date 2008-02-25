
module Ruvi
   class EditorApp

    def setup_default_command_set

        @cmd_overrides = {}
        @commands = {}
        @cmds = {}

        setup_cmd("set", /^set\s+(.*?)=(.*)/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            key, val = $1, $2
            @settings[key.to_sym] = val
        }

        setup_cmd("sp'lit", /^sp(lit)?/) {
            |ctx|
            buffer_copy = ctx.buffer.make_copy
            @docview_to_ruler[@docview2].buffer = buffer_copy
                               @docview2.buffer = buffer_copy
            @current_docview = @docview
            @settings[:split] = "true"
            status_bar_edit_line "you have to be insane to use this. split is totally messed up atm"
        }

        setup_cmd("q!", /^q!$/) {
            |ctx|
            bufs = buffers_to_save
            buffer = ctx.buffer
            if bufs.length > 1
                dbg(:quit) { "u11" }
                if !buffer.dlog.invalidated?
                    dbg(:quit) { "u12" }
                    status_bar_edit_line "closing reverted buffer!"
                    @buffers.delete buffer
                    switch_to_buffer
                    remove_unneeded_statusbars
                    redraw buffer
                else
                    dbg(:quit) { "u13" }
                    status_bar_edit_line "more than one file unsaved! use :qa! to revert all!"
                end
            elsif bufs.length == 1 and bufs.first == buffer
                dbg(:quit) { "u14" }
                bufs.first.dlog.revert_to_save_point # there can be only one!!! :P
                Curses.end_it_all
            elsif !buffer.dlog.invalidated?
                dbg(:quit) { "u15" }
                @buffers.delete buffer
                Curses.end_it_all if buffers_to_save.length == 0
                switch_to_buffer
                remove_unneeded_statusbars
                redraw buffer
            end
        }

        setup_cmd("qk", /^qk$/) {
            |ctx|
            Curses.end_it_all
        }

        setup_cmd("q'uit", /^q$/) {
            |ctx|
            buffer = ctx.buffer
            num_real_bufs = real_buffers.length
            if num_real_bufs > 0 and buffer.dlog.invalidated?
                dbg(:quit) { "u01" }
                status_bar_edit_line "file unsaved!"
            elsif num_real_bufs > 0
                dbg(:quit) { "u02" }
                @buffers.delete buffer
                switch_to_buffer nil
                remove_unneeded_statusbars
            end
            unless real_buffers.length > 0 
                dbg(:quit) { "u03" }
                Curses.end_it_all 
            else
                dbg(:quit) { "u04" }
                redraw buffer
            end
        }

        setup_cmd("new", /^new$/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            buf = EditorApp.new_buffer self, :need_bnum
            switch_to_buffer buf
            redraw buf
        }

        setup_cmd("e,ed,edit", /^e(?:d(?:it)?)?\s+(.+)$/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            fname = $1
            fname.sub! "~", ENV["HOME"]
            switch_to_buffer EditorApp.load_file_as_buffer(self, fname)
        }

        setup_cmd("r,r!", /r(!\s*(.*$)|\s+(.*$))/) {
            |ctx|
            # TODO - test
            ctx.cmd_line =~ ctx.re
            lines = nil
            is_cmd = !$2.nil?
            lines = is_cmd ? exec_into_buffer_lines($2) : EditorApp.file_to_buffer_lines($3)
            ctx.buffer.lines[ctx.buffer.y, 0] = lines
            redraw ctx.buffer
        }

        setup_cmd("b'uffer", /^b(.+)$/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            buf = @buffers.detect { |b| b.bnum == $1.to_i }
            if buf.nil?
               status_bar_edit_line "No such buffer"
            else
               switch_to_buffer buf
            end
        }

        setup_cmd("w,wa,wq", /^w(q|a|\s+(.+))?$/) { # TODO - add in waq?
            |ctx|
            ctx.cmd_line =~ ctx.re
            buffer = ctx.buffer
            case $1
            when "a"
                error = false
                each_real_buffer {
                    |buffer| 
                    next if !buffer.dlog.invalidated? # don't save out untouched files
                    if buffer.fname.nil?
                        status_bar_edit_line "ERROR - unnamed file on buffer #{buffer.bnum}"
                        error = true
                        break
                    end
                    save_buffer_as_file buffer
                }
                status_bar_edit_line "saved all files" unless error
            when "q"
                if !buffer.fname.nil?
                    # TODO - notify when other files are unsaved!!!
                    save_buffer_as_file buffer
                    Curses.end_it_all
                else
                    status_bar_edit_line "ERROR - unnamed file on buffer #{buffer.bnum}"
                end
            when nil
                # TODO - add a test case for this..
                if !buffer.fname.nil?
                    save_buffer_as_file buffer
                    status_bar_edit_line "saved"
                else
                    status_bar_edit_line "ERROR - unnamed file on buffer #{buffer.bnum}"
                end
            else
                fname = $2
                fname.sub! "~", ENV["HOME"] unless fname.nil?
                if fname.nil?
                    status_bar_edit_line "ERROR - unnamed file on buffer #{buffer.bnum}"
                else
                    save_buffer_as_file buffer, fname # write it to a file with a suffix
                    status_bar_edit_line "written out to: #{fname}"
                end
            end
        }

        # NOTE - this one just doesn't fit in with any completion plan i can come up with!!! - *has* to be a override
        setup_cmd_override(/^([0-9]+)$/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            buffer = ctx.buffer
            x = get_indent_level buffer.lines[buffer.y]
            buffer.move_to(x, $1.to_i - 1)
            buffer.top = buffer.y
            redraw buffer
        }
    end


 end
 end
