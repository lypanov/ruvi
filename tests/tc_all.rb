#!/usr/bin/ruby

$:.unshift(File.dirname((File.readlink($0) rescue $0)) + "/../lib/") unless $win32 
$test_case = true

require "test/unit"
require "shikaku"
require "plugins/hl_ae"
require "plugins/hl_plain"
require "plugins/hl_cpp"
require "plugins/completion"
require "plugins/rrb_plugin"
require "zlib"
require "yaml"
require "lab"
require "singleton"
require 'fileutils'
require 'tempfile'

include Ruvi

module Ruvi

class WinDesc
    attr_accessor :x, :y, :sx, :sy, :win
    def initialize x, y, sx, sy
        @x, @y, @sx, @sy = x, y, sx, sy
        @win = nil
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

class Twt
   attr_writer :desc
   include LabThingy
   def initialize editor
      init_lab_thingy editor
   end
   def maxx
      WinDescs::instance.stdscr.maxx
   end
   def maxy
      WinDescs::instance.stdscr.maxy
   end
   def render
   end
   def to_internal
      InternalRendering.new @editor.buffer, @editor.attr_buffer
   end
   def to_html
      output = ""
      @editor.buffer.each_with_index {
         |line, y|
         line.gsub!(/\s+$/, "")
         output << "<pre>#{line}
                    </pre><br>"
      }
      output
   end
end

$lab_disabled = true

class MyEdTestStub
   include Lab
   def initialize
      @twt = Twt.new self
      init_buffer_abstraction
   end
   def do_rendering
      begin
         $lab_disabled = false
         yield
      ensure
         $lab_disabled = true
      end
   end
   def refresh
      @twt.render
   end
   def to_html ; @twt.to_html ; end
   def to_internal ; @twt.to_internal ; end
end

class Blah
   def maxx
       @desc.sx
   end
   def maxy
       @desc.sy
   end
   def setpos y, x # curses interface is swapped...
       $myedteststub.setpos @desc.y + y, @desc.x + x
   end
   def clear *k; $myedteststub.clear(*k); end
   def set_attr *k; $myedteststub.set_attr(*k); end
   def addstr *k; $myedteststub.addstr(*k); end
   def refresh *k; $myedteststub.refresh(*k); end
   def initialize desc
       @desc = desc
   end
end

module Curses
    def Curses.relayout_all
        WinDescs::instance.descs.each_value { 
            |desc| 
            desc.win = Blah.new desc
        }
    end
    def Curses.begin_draw desc
        Curses.relayout_all if desc.win.nil?
        desc.win
    end
    def Curses.int_init
        $was_closed = false
        $myedteststub = MyEdTestStub.new
        scr = Blah.new WinDesc.new(0, 0, 100, 20)
        WinDescs::instance.stdscr = scr
        EditorApp.perform_layout
    end
    def Curses.int_finish
    end
    def Curses.close_screen
        $was_closed = true
    end
    def Curses.end_it_all
        close_screen
    end
end

module Ruvi

$user_input = []
class EditorApp
    def get_user_input question = ""
       $user_input_question = question
       return $user_input.shift
    end
end

end

class TextWithCursor
   attr_reader :x, :y, :lines, :extension
   def initialize text, extension = nil
      lines = text.split "\n"
      lines.shift until lines.first.length > 0 and !(lines.first =~ /^\s+\#/)
      first_line = lines.shift
      x_xpos = first_line.index "X"
      y_xpos, x_offset = nil, nil
      y_offset = 0 # we always begin test case on first line
      # find offset of cursor X, an thusly the y
      lines.each_with_index { 
         |line, idx| 
         pos = line.index "X"
         if !pos.nil?
            x_offset = pos + 2
            @y = idx
            break
         end
      }
      fail "sorry, ur test case sucks" if x_offset.nil?
      # cut out the indent spaces and the X
      lines.each { |line| line.slice! 0, x_offset }
      @lines = lines
      @x = x_xpos - x_offset
      @extension = extension
   end
   def buffer_lines
      self.lines.collect { |l| BufferLine.new l }
   end
   def text
      lines.join "\n"
   end
end   

class TC_MyTest < Test::Unit::TestCase

   def send_cmd cmd
      puts "EXECUTING COMMAND #{cmd.inspect}" if defined? DO_TEST
      cmd.each_byte {
         |byte| 
         @app.send_key byte
      }
   end

   # :finalize_only
   def do_kill_difflogs *options
      # remove difflogs to prevent replay thusly messing up the do_test_case state independancy completely
      @app.buffers.each {
         |buffer| 
         buffer.dlog.finalize
         File.delete buffer.dlog.difflog_fname if File.exists? buffer.dlog.difflog_fname and !(options.include? :finalize_only)
      }
   end

   def reset_create_and_switch_to kill_difflogs = true
      do_kill_difflogs if kill_difflogs
      @app.reset_state
      setup_test_settings
      buf = EditorApp.new_buffer @app, :need_bnum
      @app.switch_to_buffer buf
      buf
   end

   def do_test_case before_str, *states
      fail "sorry, you need a even number of state specifiers!" if (states.length % 2) == 1

      before = (before_str.is_a? String) ? TextWithCursor.new(before_str) : before_str

      buf = reset_create_and_switch_to
      buf.fname = "blub.#{before.extension || "txt"}"
      buf.lines = before.buffer_lines
      buf.x, buf.y = before.x, before.y

      state_number = 0

      until states.empty?
         cmd, after_str = *(states.slice! 0..1)

         send_cmd cmd

         buf = @app.current_buffer

         after = TextWithCursor.new after_str

         assert_equal([@app.show_line_with_marker(buf, Point.new(after.x, after.y), after.lines[after.y]), 
                       after.lines.collect{|t|t.to_s}.join("\n"), state_number], 
                      [@app.show_line_with_marker(buf, Point.new(buf.x, buf.y),     buf.lines[buf.y]),
                       buf.lines.collect  {|t|t.to_s}.join("\n"),  state_number], 
                      "Comparison failed")
         state_number += 1
      end
   end

   def setup
      @app = EditorApp.new
   end

   def teardown
      @app.finish
   end

   def startup_and_load fname
      @app.reset_state
      setup_test_settings
      buf = EditorApp.load_file_as_buffer @app, fname
      @app.switch_to_buffer buf
      buf
   end

   def restart_with_difflog fname, debug = false
      do_kill_difflogs :finalize_only
      @app.reset_state
      setup_test_settings
      buf = EditorApp.load_file_as_buffer @app, fname
      @app.switch_to_buffer buf
      buf
   end

   def setup_test_settings
      @app.settings[:nu] = "true"
   end

   def do_highlight_case buf, dot_extension, id, code
      buf.fname = "mytest#{dot_extension}"
      buf.lines = code.split("\n").collect { |line| BufferLine.new line }
      check_rendering buf, id
   end

   def check_rendering buf, id
      @app.redraw buf
      @app.flush_finish_redraw buf
      # TODO turn back on
      assert InternalRendering.verify_rendering(id)
   end

end

require 'tests/testcases.rb'

require 'test/unit/ui/console/testrunner'
Test::Unit::UI::Console::TestRunner.run(TC_MyTest)
