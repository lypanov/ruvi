#!/usr/bin/ruby

# Copyright 2003-2004 Alexander Kellett (ruvi [at] lypanov [dot] net)
# Released under 3 clause BSD license : IOW sans advertising clause.

# TODO - major todo item, ctrl-arrow key should do a whitespace movement, quite complex, 
#        vert it should go to the end of the block in the programming language 
#           - by finding the first line on which the indentation is lower than the current x position
#        horiz it should just skip whitespace, like e on whitespace - maybe this already exists in vim??? - if so, copy the binding!

$version_number = "0.4.12"

$VERBOSE = nil

require 'thread'
require '3rdparty/breakpoint'

# TODO - move somewhere nice...
def limit_to_positive num
    return 0 if num < 0
    num
end

# TODO - includes are in a ugly place...
require "curses" unless defined? Curses 
require "singleton"
require "optparse"
require "debug.rb"
require "baselibmods.rb"

# can't we indent here?
module Ruvi

# addins to std libs

# various misc abstractions

require "misc.rb"

# TODO remove the struct replace with the "real thing"

end

require "highlighters.rb"
require "widgets.rb"
require "buffer.rb"
require "movement.rb"
require "timemachine.rb"
require "bindings/bindings.rb"
require "bindings/bindings2.rb"
require "search.rb"
require "commands.rb"
require "selections.rb"
require "front.rb"
require "virtualbuffers.rb"

module Ruvi

class EditorApp

    # TODO we should replace all this bullshit - by translating all the possible curses keys
    ASCII_UPPER    = 255
    CR_KEY         = 13
    BACKSPACE_KEYS = [8, 127, 263]
    ESC_KEY        = 27

    # too many attributes!!!!!
    attr_reader :current_buffer
    attr_reader :history_buffer, :main_paste_buffer, :debug_buffer
    attr_reader :buffers
    attr_reader :selection, :hl_selection
    attr_reader :status_bar
    attr_reader :widgets
    attr_reader :change_listeners
    attr_accessor :end_char_mode, :settings, :docview_to_ruler, :docview2
    attr_accessor :mutex

    # TODO move out...
    SearchContext = Struct.new(:reverse, :history_pos, :already_performed, :got_no_key, :string)

    # TODO these config routines are ugly... make them generic somehow!

    def config_get_nu
        @settings[:nu] == "true"
    end

    def config_get_split
        @settings[:split] == "true"
    end

    def config_get_tw
        @settings[:tw].to_i
    end

    def config_get_sw
        @settings[:sw].to_i
    end

    def config_get_tab_size
        @settings[:ts].to_i
    end

    class Settings < Hash
        attr_accessor :procs, :gens
        def initialize
            super
            @gens = {}
            @procs = {}
        end
        def [](a)
            @gens.has_key?(a) ? @gens[a].call : super(a)
        end
        def []=(a, b)
            super a, b
            @procs[a].call if @procs.has_key? a
        end
    end

    def initialize
        reset_state
    end

    def EditorApp.app_instance
        @@app
    end

    # TODO this is hecka big, can't we seperate out more stuff?
    def reset_state
        @@app = self

        @needs_full_redraw = false

        BufferIdAllocator::instance.max_buffer_idx = 1

        BufferListing::instance.clear

        @mutex = Mutex.new

        @current_paste_buffer = nil

        @doing_macro = nil
        @macros = []

        @change_listeners = []
        @change_listeners << self.method(:notify_of_change)

        @changed = false

        @mode_stack = [:normal]
        
        Curses.int_init

        @curses_key_translators = {}

        @current_command_binding_state = nil
        @current_insert_binding_state = nil
        @stored_command_bindings = {}
        @stored_insert_bindings = {}
        
        setup_bindings
        
        @search_history = []
        
        @buffers = []
        @current_buffer = nil
        
        @number = nil
        
        @end_char_mode = false
        @replace_mode  = false
        @replace_single_letter = false
        @search        = nil

        @da_command    = ""
        
        @status_bar = nil
        
        @selection = nil
        @hl_selection = nil
        
        @command, @cmd_line = "", ""
        
        @paste_buffers = {}
        @main_paste_buffer = EditorApp.new_buffer self, :no_blank_line, :fake_buffer
        @main_paste_buffer.is_paste_buffer = true
        @history_buffer = EditorApp.new_buffer self, :no_blank_line, :fake_buffer
        @debug_buffer   = EditorApp.new_buffer self, :no_blank_line, :fake_buffer
        Debug::instance.register_debug_buffer @debug_buffer
        dbg(nil) { "--- beginning debug output #{Time.now.to_s} ---" } unless $test_case

      # root

        @root           = VBox.new self, nil

      # window 1

        @doc_with_ruler = HBox.new self, @root

        @docview        = DocView.new self, nil
        @docview.parent = @doc_with_ruler

        @ruler          = Ruler.new self, nil
        @ruler.parent   = @doc_with_ruler

      # window 2

        @doc_with_ruler2 = HBox.new self, @root

        @docview2        = DocView.new self, nil
        @docview2.parent = @doc_with_ruler2

        @ruler2          = Ruler.new self, nil
        @ruler2.parent   = @doc_with_ruler2

        @docview_to_ruler = {
            @docview  => @ruler,
            @docview2 => @ruler2,
        }

        @current_docview = @docview

        @focus = @docview

        @widgets =  [@root, @doc_with_ruler, @docview]
        
        # DEFAULTS
        @settings = Settings.new # maybe arguments should be registered with types?????, or use a callback system to verify typing???
        @settings[:sw] = "4"
        @settings[:ts] = "8"
        @settings[:tw] = nil
        @settings[:nu] = "false"
        @settings[:split] = "false"
        @settings[:autopair] = "false"

        @settings.procs[:nu] = proc {
            update_split_state
            update_ruler_state
        }

        update_split_state
        update_ruler_state

        @settings.procs[:split] = proc {
            update_split_state
            update_ruler_state
        }

        setup_default_command_set
    end

    def update_split_state
        [@doc_with_ruler2, @docview2].each { |w| @widgets.delete w }
        status_bars = @widgets.find_all { |sb| sb.is_a? StatusBar }
        idx_of_first_status_bar = @widgets.index status_bars.first
    if config_get_split
      if idx_of_first_status_bar.nil?
        @widgets += [@doc_with_ruler2, @docview2] if config_get_split
      else
        @widgets.insert_after(idx_of_first_status_bar - 1, @docview2)
        @widgets.insert_after(idx_of_first_status_bar - 1, @doc_with_ruler2)
      end
    end
        EditorApp.perform_layout
    end

    def update_ruler_state
        @widgets.delete @ruler
        @widgets.insert_after @widgets.index(@doc_with_ruler), @ruler if config_get_nu
        idx = @widgets.index(@doc_with_ruler2)
        if !idx.nil?
        @widgets.delete @ruler2
        @widgets.insert_after idx, @ruler2 if config_get_nu
        end
        EditorApp.perform_layout
    end

    def finish
        Curses.int_finish # ext
    end

    def each_real_buffer
        @buffers.each {
            |buffer|
            next if buffer.fake_buffer
            yield buffer
        }
    end

    def real_buffers
        buffs = []
        each_real_buffer { 
           |b| buffs << b 
        }
        buffs
    end

    class BufferIdAllocator
        include Singleton
        attr_accessor :max_buffer_idx
    end

    def self.alloc_new_buffer
        BufferIdAllocator::instance.max_buffer_idx += 1
        (BufferIdAllocator::instance.max_buffer_idx - 1)
    end

    def remove_unneeded_statusbars
        count_was = @widgets.length
        @widgets.delete_if {
           |sb|
           (sb.is_a? StatusBar) and !(@buffers.include? sb.buffer)
        }
        EditorApp.perform_layout if count_was != @widgets.length
    end

    def new_status_bar buf
        status_bar = StatusBar.new self, buf
        status_bar.parent = @root
        @widgets << status_bar
        EditorApp.perform_layout
        status_bar
    end

    def self.new_buffer app, *options
        fname         = options.detect { |opt| opt.is_a? String }
        no_blank_line = options.include? :no_blank_line
        fake_buffer   = options.include? :fake_buffer
        needs_bnum    = options.include? :need_bnum
        delay_edlog_load = options.include? :delay_edlog_load
        bnum = needs_bnum ? alloc_new_buffer : nil
        buf = DocumentBuffer.new app
        app.buffers << buf # TODO - sucky caller should do @buffers << ?
        buf.lines << BufferLine.new("") unless no_blank_line
        buf.fake_buffer = true if fake_buffer
        app.new_status_bar buf if needs_bnum
        fail "are you sure you want to have #{buf.fname} set and delay_edlog_load == #{delay_edlog_load}" \
          if !buf.fname.nil? and delay_edlog_load 
        buf.dlog.load_or_create_difflog unless delay_edlog_load
        buf.fname = fname unless fname.nil?
        buf.bnum = bnum
        buf
    end

    def self.file_to_buffer_lines fname
        buffer_lines = []
        File.open(fname, "r") { 
            |fp|
            fp.each_line { 
                |l|
                buffer_lines << BufferLine.new(l.chomp)
            }
        }
        buffer_lines
    end

    def self.load_file_as_buffer app, fname
        buf = self.new_buffer app, fname, :no_blank_line, :need_bnum, :delay_edlog_load
        if $replaying
            buf.lines = $action_replay_log.buffers_loaded[fname]
        else
        begin
            buf.lines += self.file_to_buffer_lines(fname)
        rescue => e
            # wait for user to :w rather than failing now           
            status_bar_edit_line "file not found: creating empty buffer" unless @status_bar.nil?
        end
        $action_replay_log.buffers_loaded[fname] = buf.lines
        end
        buf.lines << "" if buf.lines.empty?
        buf.dlog.load_or_create_difflog
        buf.update_highlighter
        buf
    end

    def switch_to_buffer buf = @last_buffer
        @last_buffer = @current_buffer
        buf = real_buffers.first if (!@buffers.include? buf) or buf.nil?
        @current_buffer = buf
        buffer_changed_to buf
        return if buf.nil?
        # TODO need to fully clear screen here in case of short buffers?
        redraw buf
        @status_bar = @widgets.detect { |sb| (sb.is_a? StatusBar) and (sb.buffer == buf) }
        @status_bar = new_status_bar(buf) if @status_bar.nil?
    end

    def save_buffer_as_file buffer, fname = nil
        fname = buffer.fname if fname.nil?
        raise "save_buffer_as_file called for buffer without a valid fname" if fname.nil?
        File.open(fname, "w") { |fp|
            buffer.dlog.saved
            buffer.lines.each { |line| fp.puts line }
        }
    end

    def invalidate_screen_line buffer, y
        buffer.redraw_list << y + buffer.top
    end

    def EditorApp.invalidate_buffer_line buffer, y
        buffer.redraw_list << y
    end

    def curs_x
        current_docview.cursor.x
    end

    def curs_y
        current_docview.cursor.y
    end

    attr_reader :current_docview

    def buffer_changed_to buffer
        current_docview.buffer = buffer
        @docview_to_ruler[current_docview].buffer = buffer
    end

    REFRESH_EVERY_N_LINES = 20

    def flush_finish_redraw buffer
        buffer = nil # we *totally* ignore buffer now!, so lets remove it from the method prototype soon!
        position_cursor current_docview.buffer, current_docview
        watched_buffers = []
        @widgets.each { 
            |w| 
            next unless w.is_a? DocView
            watched_buffers << w.watch_buffer unless watched_buffers.include? w.watch_buffer
        }
        nts = nil
        redraw_was_needed = false
        unwatching_buffers = @widgets.dup
        watched_buffers.each {
            |buffer| 
            watching_buffer = @widgets.find_all { |w| w.watch_buffer == buffer }
            watching_buffer.each {
                |widget|
                unwatching_buffers.delete widget
            } 
            if buffer.needs_redraw or @needs_full_redraw
                redraw_was_needed = true
                redraw buffer
            elsif 
                buffer.redraw_list = buffer.redraw_list.sort.uniq
                if buffer.got_a_scroll_already
                    watching_buffer.each {
                        |widget|
                        widget.canvas.scrl buffer.need_to_scroll
                    }
                    nts = buffer.need_to_scroll
                    buffer.need_to_scroll = 0
                end
            end
            buffer.needs_redraw = false
            buffer.got_a_scroll_already = false
        }
        @needs_full_redraw = false
        lines_done = 0
        unwatching_buffers.each {
            |widget|
            next if widget.kind_of? Box
            (0...widget.height).each {
               |y|
               widget.render y
               refresh_widgets if (lines_done % REFRESH_EVERY_N_LINES) == 0
               lines_done += 1
            }
        }
        refresh_widgets
        watched_buffers.each {
            |buffer|
            buffer.redraw_list.delete_if { |y| (y < buffer.top) or (y > buffer.top + screen_height) }
            last_dirty_list     = buffer.dirty_list || []
            new_y               = buffer.y
            buffer.dirty_list   = [new_y, new_y - (nts || 0)]
            buffer.redraw_list += last_dirty_list
            buffer.redraw_list += buffer.dirty_list
            buffer.redraw_list = buffer.redraw_list.sort.uniq
            watching_buffer = @widgets.find_all { |w| w.watch_buffer == buffer }
            buffer.redraw_list.each {
                |y| 
                watching_buffer.each {
                    |widget|
                    dbg(:dbg_highlight) { "rendering #{y} for widget type #{widget.type}" }
                    widget.render y - buffer.top
                    refresh_widgets if (lines_done % REFRESH_EVERY_N_LINES) == 0
                    lines_done += 1
                }
            }
            buffer.redraw_list = []
        }
        if !nts.nil? or redraw_was_needed
            # we clear the bottom line of the buffer 
            # as the text scrolling appears to draw 
            # outside its draw area
            descs = [WinDescs::instance.descs[@docview]]
            descs << WinDescs::instance.descs[@docview2] if @widgets.include? @docview2
            descs.each {
            |desc|
            scr = WinDescs::instance.stdscr
            scr.set_attr false, Curses::COLOR_WHITE, Curses::COLOR_BLACK
            scr.setpos(desc.y + desc.sy - 1, 0) # y, x
            scr.addstr " " * (scr.maxx - 1)
            scr.refresh
        }
        end
        refresh_widgets
        display_cursor current_docview.buffer, current_docview
    end

    def refresh_widgets
        @widgets.each { 
            |widget| 
            next if widget.kind_of? Box
            widget.canvas.refresh 
        }
    end

    def position_cursor buffer, docview
        current_line = buffer.lines[buffer.y]
        string_upto_now = current_line.slice(0...buffer.x)
        x = string_upto_now.unpack("c*").inject(0) { |width, char| width += (char == ?\t ? config_get_tab_size : 1) }
        ecm_diff = (@end_char_mode and @mode_stack.last == :insert and !current_line.empty?) ? 1 : 0
        docview.absolute_cursor.x, docview.absolute_cursor.y = buffer.x + ecm_diff, buffer.y - buffer.top
        docview.cursor.x, docview.cursor.y = x + ecm_diff, buffer.y - buffer.top
    end

    def display_cursor buffer, docview
        @focus.canvas.setpos docview.cursor.y, docview.cursor.x # y, x
        @focus.canvas.refresh
    end

    def redraw_from_and_including buffer, y
        buffer.invalidate_line_highlight y
        (y...screen_height).each { |y| 
            invalidate_screen_line buffer, y
        }
    end
    
    def redraw buffer
        @widgets.each { |sb| sb.invalidate if sb.is_a? StatusBar }
        buffer.redraw_list = [] # no point invalidating everything twice so lets clear the list!
        redraw_from_and_including buffer, 0
    end

    def line_displayed? buffer, y
        (((buffer.top)..(buffer.top + screen_height - 1)) === y)
    end

    def get_indent_level line
        line =~ /^(\s*)/
        return $1 ? $1.length : 0
    end
    
    def clear_buffers_with_extension extension
        @buffers.delete_if {
            |b| 
            b.kind_of? extension
        }
    end
    
    def get_word_under_cursor buffer, *options
        ruby_vars = (options.include? :look_for_ruby_variables)
        x_was = buffer.x
        next_word(buffer, :letter_after, :reverse)
        # begin
        x_pos_test_1 = buffer.x
        next_word(buffer, :letter_after) # test to see if we were start of string
        if buffer.x == x_was
            # we were already at the start, so we went too far
            # pass as we are back where we should be now anyway
        else
            # we are now at the start of a word
            buffer.x = x_pos_test_1
        end
        # end
        x_pos1 = buffer.x
        next_word(buffer, :letter_after)
        x_pos2 = buffer.x
        buffer.x = x_was
        if ruby_vars
            prev_char = (buffer.lines[buffer.y][x_pos1-1] rescue 0)
            x_pos1 -= 1 if [?$, ?@].include? prev_char
            if  prev_char == ?@ \
            and (buffer.lines[buffer.y][x_pos1-1] rescue 0) \
             == ?@
                x_pos1 -= 1
            end
        end
        return x_pos1...x_pos2 
    end

    def itr_forewards buffer, tok, y
        buffer.ensure_line_highlight y
        idx = buffer.tokens[y].index tok
        buffer.tokens[y].slice(idx..-1).each { |tok| yield y, tok }
        return if buffer.lines.length == y
        (y+1).upto(buffer.last_line_num) {
            |ny|
            buffer.ensure_line_highlight ny
            buffer.tokens[ny].each { |tok| yield ny, tok }
        }
    end

    def itr_backwards buffer, tok, y
        buffer.ensure_line_highlight y
        idx = buffer.tokens[y].index tok
        buffer.tokens[y].slice(0...idx).reverse_each { |tok| yield y, tok }
        return if y == 0
        (y-1).downto(0) {
            |ny|
            buffer.ensure_line_highlight ny
            buffer.tokens[ny].reverse_each { |tok| yield ny, tok }
        }
    end

    def token_itr buffer, tok, y, forwards, &block
        if forwards
            itr_forewards buffer, tok, y, &block
        else
            itr_backwards buffer, tok, y, &block
        end
    end

    def pop_paste_buffer
        choice = @current_paste_buffer
        @current_paste_buffer = nil
        buf = choice.nil? ? @main_paste_buffer : @paste_buffers[choice]
        if buf.nil?
            buf = EditorApp.new_buffer self, :no_blank_line, :fake_buffer
            buf.is_paste_buffer = true
            @paste_buffers[choice] = buf
        end
        buf
    end

    def notify_of_change the_change, direction
        @changed = true
    end

    def calculate_autoindent buffer, line, my_y, deindent_block
        current_line = line
        current_line =~ /^(\s*)/
        indent_level = $1 ? $1.length : 0
        buffer.ensure_line_highlight my_y # ummm does current_line need to be used?
        # list of indenting keywords
        last_hlstack = (my_y == 0) ? [] : buffer.hlstacks[my_y - 1]
        hlstack      = buffer.hlstacks[my_y]
        last_hlstack = [] if last_hlstack.nil?
        hlstack      = [] if      hlstack.nil?
        # if hlstack is bigger than previous hlstack then an indent is required
        if hlstack.length > last_hlstack.length
            bras = hlstack.reject { |k| k.str != "(" }
            kets = hlstack.reject { |k| k.str != ")" }
            if bras.length > kets.length
                indent_level = current_line.rindex("(") + 1
            else
                indent_level += config_get_sw
            end
        elsif hlstack.length < last_hlstack.length
            diff = -config_get_sw
            was_bra = (last_hlstack[-1].str == "(")
            if was_bra
                da_y = my_y
                ridx = nil
                while true
                    ridx = buffer.lines[da_y].rindex "("
                    break if !ridx.nil?
                    da_y -= 1
                end
                indent_level = get_indent_level(buffer.lines[da_y])
            elsif deindent_block
                y = my_y
                DiffLogger::ModifyLineChange.new(buffer, y) {
                    line = buffer.lines[y]
                    line.slice! 0, indent_level
                    indent_level = [(indent_level + diff), 0].max
                    ecm = @end_char_mode
                    buffer.move_to_x [(buffer.x + diff), 0].max
                    @end_char_mode = ecm
                    line[0, 0] = (" " * indent_level)
                }
            end
        end
        (" " * indent_level)
    end

    def exec_into_buffer_lines cmd
        buffer_lines = []
        IO.popen(cmd) {
            |io|
            while not io.eof?
                buffer_lines << BufferLine.new(io.gets)
            end
        }
        buffer_lines
    end
    
    def buffers_to_save
        buffers = []
        each_real_buffer {
            |buffer| 
            buffers << buffer if buffer.dlog.invalidated?
        }
        buffers
    end

    def setup_extensions
        setup_cmd("sc", /^sc$/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            fname = ctx.buffer.fname
            buf = EditorApp.new_buffer self, :no_blank_line
            buf.lines += exec_into_buffer_lines "ruby -wc #{fname} 2>&1"
            switch_to_buffer buf
        }
        setup_cmd("tlaci,diff", /^((tlaci)|(diff))$/) {
            |ctx|
            ctx.cmd_line =~ ctx.re
            diff_only = $2.nil?
            cmd = "tla changes --diffs 2>&1"
            buf = nil
            if diff_only
                buf = EditorApp.new_buffer self, :no_blank_line
            else
                log_file_fname = `tla make-log`.chomp
                buf = EditorApp.load_file_as_buffer self, log_file_fname
            end
            buf.lines += exec_into_buffer_lines cmd
            switch_to_buffer buf
        }
    end

    def screen_height
        # when using the actual screen height the last char drawn on the last line 
        # appears to scroll the screen up one thus completely messing up the rendering
        WinDescs::instance.descs[@docview].sy - 1
    end

    def ensure_buffer_highlighted buffer, pass = false
        while true
            @mutex.synchronize {
                line_num = buffer.first_non_highlighted_line
                if line_num.nil? or line_num > buffer.lines.length
                    @status_bar.highlight_progress = nil
                    return
                end
                buffer.ensure_line_highlight line_num
            }
            Thread.pass if pass
        end
    end

    def load_script_file scriptfname
        File.open(scriptfname) { 
            |file| 
            content = file.gets nil
            eval content
        }
    end

    def start_background_highlighter
        Thread.new {
            while true
               # FIXME - 
               #  maybe we should include some of the buffers listed by
               #  a call to BufferListing::instance.open_buffers once we
               #  are finished with the current_buffer?
               [current_buffer].each {
                  |buffer|
                  next if buffer != current_buffer
                  ensure_buffer_highlighted buffer
               }
               sleep 5
            end
        }
    end

    def EditorApp.join_next_line_onto_this buffer, myy
        # join current line onto previous line - move to old end of last line
        line_to_join = nil
        DiffLogger::RemoveLineChange.new(buffer, myy+1) {
            line_to_join = buffer.lines.delete_at(myy+1)
        }
        DiffLogger::ModifyLineChange.new(buffer, myy) {
            join_to = buffer.lines[myy]
            buffer.move_to_x join_to.length
            join_to << line_to_join
            EditorApp::app_instance.redraw buffer # should actually just redraw from this point on
        }
    end

end

$action_replay_log = ReplayLog.new ARGV, [], {} unless defined? $action_replay_log
$replaying = false unless defined? $replaying
$load_difflogs = false
Thread.abort_on_exception = true

unless $test_case
   trap("USR1") { raise "waza" } unless $win32 
   buf = nil
   opts = OptionParser.new { 
      |opts|
      opts.banner = "Usage: ruvi [--version] [filename+]"
      opts.separator ""
      opts.separator "Specific options:"
      opts.on_tail("--recover", "Replay/load modification logs [EXPERIMENTAL]") {
         $load_difflogs = true
      }
      opts.on_tail("--version", "Show version") {
         Curses.close_screen
         puts "Ruvi Version : #{$version_number}"
         exit
      }
   }
   app = EditorApp.new
   begin
      plugin_dir = File.dirname(__FILE__) + "/plugins"
      Dir[plugin_dir + "/*"].find_all { 
         |filename| 
         filename =~ /.*\.rb/ 
      }.each {
         |plugin_fname|
         require plugin_fname
      }
      rcfname = "#{ENV["HOME"]}/.ruvirc"
      app.load_script_file rcfname if File.exists? rcfname
   rescue => e
      Curses.close_screen
      puts e.inspect
      puts e.backtrace.join("\n")
      exit
   end
   arguments = begin
                  opts.parse! $action_replay_log.argv
               rescue
                  Curses.close_screen
                  puts "Invalid command line options specified"
                  puts opts.banner
                  exit
               end
   arguments.each {
      |filename| 
      buf = EditorApp.load_file_as_buffer app, filename
   }
   buf = EditorApp.new_buffer app, :need_bnum if arguments.empty?
   app.switch_to_buffer buf
   debug_out_fname  = "/tmp/debug_log"
   replay_out_fname = "/tmp/replay_dump"
   begin
      # app.start_background_highlighter
      if $replaying
         $action_replay_log.keys_pressed.each {
            |c|
            app.send_key c
            app.flush_finish_redraw app.current_buffer
         }
         loop {
            c = Curses.getch
            break if c == ?q
         }
      else
      app.input_loop 
      end
   rescue => e
      app.finish
      File.open(debug_out_fname, "w+") {
         |dbglog|
         message = <<EOM
------ failure -----
#{e.to_s}
----- backtrace ----
#{e.backtrace.join("\n")}
EOM
         dbglog.puts message
         puts message
         dbglog.puts "--- debug_buffer ---"
         app.debug_buffer.lines.each {
             |line|
             dbglog.puts line
         }
         dbglog.puts "---- end of log ----"
      }
      puts "wrote out: #{debug_out_fname}"
      File.open(replay_out_fname, "wb+") {
         |replay_log|
         replay_log.write Marshal.dump($action_replay_log)
      }
      puts "wrote out replay log: #{replay_out_fname}"
      exit
   ensure
      Curses.close_screen
      if app.debug_buffer.lines.length >= 1
         File.open(debug_out_fname, "w+") {
            |dbglog|
            app.debug_buffer.lines.each {
               |line|
               dbglog.puts line
            }
         }
         puts "wrote out: #{debug_out_fname}"
      end
      File.open(replay_out_fname, "wb+") {
         |replay_log|
         replay_log.write Marshal.dump($action_replay_log)
      }
      puts "wrote out replay log: #{replay_out_fname}"
   end
end

end

#korundum todo - paint.fillRect x, y, w, h, Qt::white - CRASHES!, need Qt::Brush.new(Qt::white)
