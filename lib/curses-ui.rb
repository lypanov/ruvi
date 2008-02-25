require "curses"
require "singleton"

module Ruvi
class WinDesc
    attr_accessor :x, :y, :sx, :sy, :win
    def initialize x, y, sx, sy
        @x, @y, @sx, @sy = x, y, sx, sy
        @win = nil
    end
    def to_s
        "#{@x},#{@y} x #{@sx}, #{@sy}"
    end
end

class WinDescs
   include Singleton
   attr_reader :descs
   attr_accessor :stdscr
   def initialize
       @descs = {}
   end
end
end

module Curses
    # possibly color list for completion
    # A_NORMAL, A_BOLD, A_UNDERLINE, A_BLINK, A_REVERSE, 
    # COLOR_BLACK, COLOR_RED, COLOR_GREEN, COLOR_YELLOW, 
    # COLOR_BLUE, COLOR_MAGENTA, COLOR_CYAN

    def Curses.int_init
        Curses.init_screen
        Curses.nonl
        Curses.cbreak
        Curses.noecho
        Curses.raw
        Curses.init_color_table # ext
        # thanks to Aredridel!!!
        require 'dl/import'
        DL.dlopen("libncurses.so.5") {
            |h|
            d = h.sym('ESCDELAY')
            d[0] = [15].pack("L")
        }
        scr = Curses.stdscr
        scr.keypad true unless $win32
        Ruvi::WinDescs::instance.stdscr = scr
        Ruvi::EditorApp.perform_layout
    end

    def Curses.relayout_all
        # relayout *all* windows
        Ruvi::WinDescs::instance.descs.each_value {
            |d|
            Ruvi::WinDescs::instance.stdscr.clear
            begin
                win = Ruvi::WinDescs::instance.stdscr.subwin d.sy, d.sx, d.y, d.x
            rescue => e
                # some useful debugging information if our window ever fails to layout
                Curses.close_screen
                p e
                p d.to_s
                exit
            end
            win.scrollok true
            win.keypad true unless $win32
            d.win = win
        }
    end

    def Curses.begin_draw desc
        Curses.relayout_all if desc.win.nil?
        desc.win
    end

    def Curses.int_finish
        Curses.close_screen
    end

    def Curses.end_it_all
        Curses.close_screen
        puts "quiting, and stuff"
        exit
    end

    # TODO - make private
    def Curses.pair_index(fg, bg)
        fg + bg * 8 + 1
    end

    # real curses only
    def Curses.init_color_table
        # set up colors
        start_color
        8.times { |fg|
            8.times { |bg|
                init_pair Curses.pair_index(fg, bg), fg, bg
            }
        }
    end

    class Window
        def set_attr boldness, fg_color, bg_color
            bold = boldness ? Curses::A_BOLD : Curses::A_NORMAL
            idx  = Curses.pair_index fg_color, bg_color
            self.attrset bold | Curses.color_pair(idx)
        end
    end
end

module Ruvi

class EditorApp
    KEYPRESS_COUNT_INTERVAL      = 0.1   # 0.2 - the higher this is the higher LAST_INTERVAL_KEYPRESS_COUNT is relatively
    FORCE_REDRAW_TIMEOUT         = 0.005 # 0.1
    LAST_INTERVAL_KEYPRESS_COUNT = 2     # heavily related to KEYPRESS_COUNT_INTERVAL
    SELECT_POLL_INTERVAL         = 0.02
    SUSPEND_KEYS                 = [26, 407]

    def get_user_input question = ""
        current_string = ""
        status_bar_edit_line "#{question}:"
        flush_finish_redraw current_buffer
        while true
            c = Curses.getch
            do_cmd_mode(c, current_string) {
               |ok|
               return ok ? current_string : nil
            }
            flush_finish_redraw current_buffer
        end
        fail "impossible"
    end

    def input_loop
        pagedown_count = 0
        last_draw = Time.now
        flush_finish_redraw current_buffer
        last_count_end = Time.now
        last_count = 0
        count = 0
        timeout = nil
        # main loop
        while true
            read_fds = IO.select([$stdin], nil, nil, timeout)
            # got input? if so. lets read
            unless read_fds.nil?
                c = Curses.getch
                if SUSPEND_KEYS.include? c
                    Curses.close_screen
                    Process.kill "SIGTSTP", $$
                    Curses.init_screen 
                    redraw current_buffer
                    flush_finish_redraw current_buffer
                    next
                end
                if Time.now > last_count_end + KEYPRESS_COUNT_INTERVAL
                    last_count = count
                    last_count_end = Time.now
                    count = 0
                else
                    count += 1
                end
                send_key(c)
            end
            if last_count > LAST_INTERVAL_KEYPRESS_COUNT                
                if (Time.now - last_draw) > FORCE_REDRAW_TIMEOUT
                    flush_finish_redraw current_buffer
                    last_draw = Time.now
                end
                timeout = SELECT_POLL_INTERVAL
            else
                flush_finish_redraw current_buffer
                last_draw = Time.now
                timeout = nil
            end
        end
    end
end

end
