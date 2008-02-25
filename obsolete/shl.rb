# the command for .ruvirc:

setup_cmd("sh",/^sh$/) {
    |cmd_line, re|
    cmd_line =~ re
    sh = Shell.new(@screen)
    sh.create
    while sh.run; end
    redraw
    finish_redraw
}

class Shell
    def writer
        begin
            while true
                c = @screen.getch                    
                File.open("blah", "w+") { |f| f.puts c }
                $really_needs_flush = true
                if c == 26 then # C-z
                    @reader.raise(nil)
                    return 'Suspend'
                end
                c = 8 if c == 263
                @w_pty.print c.chr
                @w_pty.flush
            end
        rescue
            @reader.raise(nil)
            return 'Exit'
        end
    end

    def draw_str str, move = true
        @screen.setpos_xy @sx, @sy
        @screen.addstr str
        @sx += str.length if move
        @screen.setpos_xy @sx, @sy
    end
    
    def flush
        $really_needs_flush = false
        draw_str $my_str
        $my_str = ""
    end

    def initialize screen
        @screen = screen

        @shells = []
        @n_shells = 0

        @r_pty = nil
        @w_pty = nil

        @sx, @sy = 0, -1

        @reader = Thread.new {
            $my_str = ""
            while true
                begin
                    next if @r_pty.nil?
                    # TODO highlight next! and TODO! - keys: "del", and buffer menu! and remember position in a buffer!
                    c = @r_pty.getc
                    if c.nil? then
                        Thread.stop
                    end
                    needs_flush = false
                    case c
                    when 27
                    when 13
                        flush
                        @sx = 0
                        if @sy >= @screen.maxy
                            # @screen.scrl 1
                        else
                            @sy += 1
                        end
                    when 7
                        # beep?
                    when 8, 127
                        @sx -= 1
                        flush
                        draw_str " ", false
                        @sx -= 1
                    when ?a..?z, ?A..?Z, \
                        32, ?., ?,, ??, ?0..?9, 45, 36, 10, 58
                        str = c.chr
                    else
                        str = "<#{c}>"
                    end
                    $my_str << str unless str.nil?
                    if $really_needs_flush || 0
                        flush
                    end
                    @screen.refresh
                rescue
                    Thread.stop
                end
            end
        }
    end

    def list
        for i in 0..@n_shells
            unless @shells[i].nil?
                print i,"\n"
            end
        end
    end

    def switch n
        if @shells[n].nil?
            print "\##{i} doesn't exist\n"
        else
            @r_pty,@w_pty = @shells[n]
            @reader.run
            if writer == 'Exit' then
                @shells[n] = nil
            end
        end
    end

    def create
        @shells[@n_shells] = PTY.spawn("/bin/bash")
        @r_pty,@w_pty = @shells[@n_shells]
        @n_shells += 1
        @reader.run
        if writer == 'Exit'
            @n_shells -= 1
            @shells[@n_shells] = nil
        end
    end

    def run
        begin
            Curses.echo
            $app.clearline @screen.maxy-1
            $app.set_status_bar ">> "
            cmd = @screen.getstr
        ensure
            Curses.noecho
        end

        case cmd
        when /^c/i
            create
        when /^p/i
            list
        when /^([0-9]+)/
            switch $1.to_i
        when /^h/
            t = $app.mbuffer
            bnum = $app.current_buffer_idx
            $app.switch_to_buffer $app.load_file_as_buffer("shl.help")
            return false
        when /^q/i
            return false
        when /^x/i
            exit
        end
        
        true
    end
end

