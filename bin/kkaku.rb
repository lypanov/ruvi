require 'Qt'
require 'singleton'
require 'lab.rb'

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

class Blah
   def maxx
       @desc.sx
   end
   def maxy
       @desc.sy
   end
   def setpos y, x # swapped in curses interface
       $daed.setpos @desc.y + y, @desc.x + x
   end
   def clear *k; $daed.clear(*k); end
   def set_attr *k; $daed.set_attr(*k); end
   def addstr *k; $daed.addstr(*k); end
   def refresh *k; $daed.refresh(*k); end
   def initialize desc
       @desc = desc
   end
end

module Ruvi
class EditorApp
    def input_loop
        puts "START"
        $kmyeditor.exec # blocks
        puts "DONE"
    end
end

module Curses
    PretendConfigureEvent = Struct.new :width, :height
    def Curses.int_init
        Curses.layout PretendConfigureEvent.new(10,10)
        $kmyeditor = MyEditor.new
        return $kmyeditor
    end
    def Curses.int_finish
        puts "closing the screen..."
        exit
    end
    def Curses.close_screen
        puts "closing the screen..."
    end
    def Curses.int_finish
    end
    def Curses.end_it_all
        exit
    end
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
    def Curses.layout event
        scr = Blah.new WinDesc.new(0, 0, event.width, event.height)
        WinDescs::instance.stdscr = scr
        EditorApp.perform_layout
    end
    COLOR_BLACK = :black
    COLOR_WHITE = :white
    COLOR_YELLOW = :yellow
    COLOR_RED = :red
    COLOR_CYAN = :cyan
    COLOR_BLUE = :blue
    COLOR_MAGENTA = :magenta
    COLOR_GREEN = :green
    KEY_END = 0
    KEY_HOME = 0
    KEY_UP = 0
    KEY_DOWN = 0
    KEY_LEFT = 0
    KEY_RIGHT = 0
    KEY_NPAGE = 0
    KEY_PPAGE = 0
end
end

class TextWidgetThingy < Qt::Widget
   def initialize editor, *k
      super(*k)
      setup_widget
      init_lab_thingy editor
      @pixmap = Qt::Pixmap.new width, height
   end
   def setup_widget
      setKeyCompression true
      setFocusPolicy Qt::Widget::StrongFocus
   end
   def keyPressEvent ev
      return unless @editor.started
      puts "keyPressEvent"
      ev.text.each_byte {
         |c| $app.send_key(c)
      }
      $app.flush_finish_redraw
      puts "keyPressEvent handled"
   end
   include LabThingy
   def resizeEvent ev
      # QWidget::resizeEvent( e ); -> super?
      super ev
      w = width  > @pixmap.width  ? width  : @pixmap.width
      h = height > @pixmap.height ? height : @pixmap.height
      tmp = Qt::Pixmap.new @pixmap
      p tmp
      p @pixmap
      puts "resize to: #{w} x #{h}"
      Ruvi::Curses.layout Ruvi::Curses::PretendConfigureEvent.new(w,h)
      @pixmap.resize w, h
      @pixmap.fill colorGroup.base
      Qt::bitBlt @pixmap, 0, 0, tmp, 0, 0, tmp.width, tmp.height
      return unless @editor.started
      invalidate_all # optimise to only rerender affect areas
   end
   def myfont
      if @myfontcache.nil?
         f = Qt::Font.new "profontwindows"
         f.setStyleHint Qt::Font::TypeWriter
         f.setPointSize 9
         @myfontcache = f
      end
      @myfontcache
   end
   def fontmetrics
      if @myfmcache.nil?
         @myfmcache = Qt::FontMetrics.new myfont
      end
      @myfmcache
   end
   def maxx
      (height.to_f / fontmetrics.width(" ").to_f).floor
   end
   def maxy
      (height.to_f / fontmetrics.height.to_f).floor
   end
   def get_qt_color_from_curses color
      case color
      when Curses::COLOR_GREEN;   c = Qt::green
      when Curses::COLOR_YELLOW;  c = Qt::yellow
      when Curses::COLOR_BLUE;    c = Qt::blue
      when Curses::COLOR_MAGENTA; c = Qt::magenta
      when Curses::COLOR_CYAN;    c = Qt::cyan
      when Curses::COLOR_RED;     c = Qt::red
      when Curses::COLOR_WHITE;   c = Qt::white
      when Curses::COLOR_BLACK;   c = Qt::black
      else 
         puts "UNHANDLED COLOR!: #{color}"
         c = Qt::red
      end
   end
   def time_this str
      t1 = Time.now
      yield
      t2 = Time.now
      puts "time (%s): %.04f" % [str, (t2 - t1)]
   end
   # TODO - boldness
   def paintEvent ev
      return unless @editor.started
      puts "paintEvent started"
      # TODO - correct efficient implemenation would use ev.region.rects, 
      # unfortunately bindings probably need modifications for the qmemarray<qrect> stuff to marshall correctly....
      # so, rather than wasting days working on the bindings, i'll reject the optimisation for now and simply
      # repaint every thing on request, yeah i know, sucks doesn't it....
      fail "exceptional: no erase" unless ev.erased

      time_this("draw one") {
         evr = ev.rect
         Qt::bitBlt self, evr.x, evr.y, @pixmap, evr.x, evr.y, evr.width, evr.height
      }
      paint = Qt::Painter.new @pixmap, self
      paint.setBackgroundMode Qt::OpaqueMode
      paint.setBackgroundColor Qt::black
      paint.setPen Qt::white
      paint.setFont myfont
      p @invalids
      if @invalidated_all
         paint.eraseRect ev.rect # optimise!
         @invalidated_all = false
      end
      rendered_ys = {}
      time_this("invalidations") {
         lh = fontmetrics.height
         lw = fontmetrics.width(" ")
         @invalids.each {
            |i|
            # for the moment lets ignore x1, x2
            next if rendered_ys[i.y] == true
            r = Qt::Rect.new self.rect
            r.moveTop lh * i.y
            x, pos = 0, 0
            run = ""
            lastx = (@editor.buffer[i.y].length - 1)
            @editor.buffer[i.y].each_byte {
               |byte| 
               attr = @editor.attr_buffer[i.y][pos]
               if (attr.nil? and pos != lastx) or run.length == 0
                  if pos == 0 and !attr.nil?
                     puts "setting pen to #{get_qt_color_from_curses attr.fg}"
                     paint.setPen get_qt_color_from_curses(attr.fg)
                     paint.setBackgroundColor get_qt_color_from_curses(attr.bg)
                  end
                  run << byte.chr
               else
                  run << byte.chr
                  r.setLeft x
                  puts "flushing run: '#{run}' @ #{x}"
                  paint.drawText r, Qt::AlignAuto, run if run.length > 0
                  x += lw * run.length
                  run = ""
                  if !attr.nil?
                     puts "setting pen to #{get_qt_color_from_curses attr.fg}"
                     paint.setPen get_qt_color_from_curses(attr.fg)
                     paint.setBackgroundColor get_qt_color_from_curses(attr.bg)
                  end
               end
               pos += 1
            }
            puts "we are here!"
            rendered_ys[i.y] = true
         }
         paint.end
      }

      if @invalids.empty?
         evr = ev.rect
         Qt::bitBlt self, evr.x, evr.y, @pixmap, evr.x, evr.y, evr.width, evr.height
      else
         Qt::bitBlt self, 0, 0, @pixmap, 0, 0, width, height
      end

      @invalids = []

      # draw cursor without double buffering
      begin 
         paint.begin self
         cw, ch = fontmetrics.width(" "), fontmetrics.height
         old_ro = paint.rasterOp
         paint.setRasterOp Qt::XorROP
         x, y, w, h = @x * cw,  @y * ch, cw, ch
         paint.fillRect x, y, w, h, Qt::Brush.new(Qt::white)
         paint.setRasterOp old_ro
      end

      puts "paintEvent finished"
   end
end

class MyEditor

   @started = false
   @@started = false

   def initialize
      app = Qt::Application.new ARGV
      @@started = false
      @twt = TextWidgetThingy.new self, Qt::Widget.new
      app.setMainWidget @twt
      @app = app
   end

   def started
      @@started
   end

   def exec
      puts "we are blocking now!"
      @@started = true
      @app.exec # blocking
   end

   def log
      @log = File.new("mylog", "w") if @log.nil?
      @log.flush
      @log
   end

   require 'lab'
   include Lab

   def refresh
      return unless @@started
      puts "got a refresh request!"
      @twt.update
      puts "finished!"
   end 

end

require 'shikaku.rb'
