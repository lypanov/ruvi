module LabThingy

   attr_accessor :x, :y
   
   def init_lab_thingy editor
      @editor = editor
      @invalids = []
      @x, @y = 0, 0
   end

   def invalidate_scan y, x1, x2
      @invalids << Struct.new(:y, :x1, :x2).new(y, x1, x2)
   end

   def invalidate_all
      # puts "invalidate_all called"
      @invalidated_all = true
      @invalids = [] # hack - need to coalesce invalids
      (0...@editor.buffer.length).each {
         |y|
         # fix, should be length of line???
         invalidate_scan y, 0, maxx 
      }
   end
   
   def maxx ; raise "must be implemented" ; end
   def maxy ; raise "must be implemented" ; end

end

module Lab

   attr_accessor :buffer, :attr_buffer

   def init_buffer_abstraction
      clear
   end

   # see caller - unneeded, as its a hack anyway
   def clear
      return if $lab_disabled
      @buffer = [""]
      @attr_buffer = []
      @twt.invalidate_all
   end

   def maxx; @twt.maxx; end

   def maxy; @twt.maxy; end

   def setpos y, x # swapped in curses interface
      @twt.x, @twt.y = x, y
      @x, @y = x, y
   end

   def set_attr boldness, fg_color, bg_color
      return if $lab_disabled
      @attr = Attr.new boldness, fg_color, bg_color
      # puts "#{boldness}, #{fg_color}, #{bg_color}"
   end

   class Attr
      attr_accessor :bold, :fg, :bg
      def initialize bold = false, fg = 0, bg = 0
         @bold, @fg, @bg = bold, fg, bg
      end
   end

   def attr_buffer_line w
      tmp = []
      w.times { tmp << Attr.new }
      tmp
   end

   def extend_attr_buffer w, h
      if !@attr_buffer.empty? and (@attr_buffer[0].length < w)
         0.upto(@attr_buffer.length) {
            |idx| 
            tmp = attr_buffer_line(w - (@attr_buffer[idx].length rescue 0))
            @attr_buffer[idx] = [] if @attr_buffer[idx].nil?
            @attr_buffer[idx] += tmp
         }
      end
      if @attr_buffer.length < h
         (h - @attr_buffer.length).times {
            @attr_buffer << attr_buffer_line(w)
         }
      end
   end

   def extend_buffer x, y, str
      if @buffer.length <= y
         (y - @buffer.length + 1).times {
            @buffer << ""
         }
      end
      if @buffer[y].length <= (str.length + x)
         @buffer[y] << " " * ((str.length + x) - @buffer[y].length)
      end
   end

   def addstr str
      return if $lab_disabled
      extend_buffer @x, @y, str
      extend_attr_buffer @x + 1, @y + 1
      if @x == @buffer[@y].length
         @buffer[@y] << str
      else
         line = @buffer[@y]
         line[@x, str.length] = str
      end
      # todo - fill in attr_buffer with nil's for runs of colour?
      @twt.invalidate_scan @y, @x, (@x + str.length)
      @attr_buffer[@y][@x] = @attr
      (@x+1).upto(@x + str.length) {
         |x| 
         @attr_buffer[@y][x] = nil
      } if str.length > 1
      @x += str.length
   end

end

class InternalRendering
   attr_accessor :buffer, :attr_buffer
   def initialize buffer, attr_buffer
      @buffer, @attr_buffer = buffer, attr_buffer
   end
   def InternalRendering.verify_rendering id
      a = InternalRendering.render_read id
      b = InternalRendering.render_get
      return true if Marshal.dump(a) == Marshal.dump(b)
      if Marshal.dump(a.attr_buffer) == Marshal.dump(b.attr_buffer)
         puts a.buffer.to_yaml
         puts b.buffer.to_yaml
         return false
      else
         puts "attr:"
         puts a.attr_buffer.to_yaml
         puts a.attr_buffer.to_yaml
         puts "text:"
         puts a.buffer.to_yaml
         puts b.buffer.to_yaml
         return false
      end
   end
   def InternalRendering.render_get
      $myedteststub.to_internal
   end
   def InternalRendering.render_read id
      fname = "tests/renderings/rendering-#{id}"
      if ! File.exists? fname
         STDERR.puts "NOTE: writing out #{fname}"
         InternalRendering.render_write id
         return render_get
      end
      str = nil
      File.open(fname) { 
         |file| 
         str = file.gets(nil)
      }
      Marshal.load str
   end
   def InternalRendering.render_write id
      File.open("tests/renderings/rendering-#{id}", "w") { |file| file.puts Marshal.dump(render_get) }
   end
end

