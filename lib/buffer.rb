require "misc.rb"

module Ruvi

ReplayLog = Struct.new(:argv, :keys_pressed, :buffers_loaded)

class BufferListing
    include Singleton
    attr_reader :open_buffers
    def initialize
        @id2buffer = {}
        @open_buffers = []
    end
    def delete buffer
        @id2buffer 
        @open_buffers.delete buffer
    end
    def clear
        @open_buffers.clear
    end
    def << buffer
        @id2buffer[buffer.id] = buffer
        @open_buffers << buffer
        ObjectSpace.define_finalizer buffer, 
                                     proc { 
                                         |id|
                                         # puts "killing buffer #{id}"
                                         self.delete buffer
                                     }
    end
end

class BufferLine < String
    include NewLineAttributes
    def initialize *k
        super(*k)
    end
    def method_missing sym, *params
        super(*params)
    end
end

class BufferLineArray < Array
    def initialize *k
        super(*k)
    end
    def method_missing sym, *params
        super(*params)
    end
end

class BufferData
    attr_accessor :lines
    attr_accessor :fname, :fake_buffer, :hlstacks, :classstacks, :tokens, 
                  :dlog, :highlighter, :redraw_list, :needs_redraw, :app, :is_paste_buffer, 
                  :highlight_cache, :dirty_list
    attr_accessor :lines_highlighted
end

module AccessorProxier
    def proxy_accessors_to_object object, *syms
    syms.map { |sym| [sym, "#{sym.to_s}=".to_sym ] }.flatten.each {
        |sym|
        define_method(sym) {
            |*k|
            self.send(object).send sym, *k
        }
    }
    end
end

class DocumentBuffer
    extend AccessorProxier
    attr_accessor :data
    proxy_accessors_to_object(:data, :lines, :fname, :fake_buffer, :hlstacks, :classstacks, :tokens, 
                  :dlog, :highlighter, :redraw_list, :needs_redraw, :app, :is_paste_buffer, 
                  :highlight_cache, :dirty_list, :lines_highlighted)
    attr_accessor :bnum, :x, :y, :top, :got_a_scroll_already, :need_to_scroll
    def first_non_highlighted_line
        extend_array_to_num @data.hlstacks, @data.lines.length
        extend_array_to_num @data.classstacks, @data.lines.length
        extend_array_to_num @data.highlight_cache, @data.lines.length
        @data.highlight_cache.index nil
    end
    def ax
        @data.app.end_char_mode ? @x + 1 : @x
    end
    def invalidate_line_highlight line_num
        @data.app.mutex.synchronize {
            _invalidate_line_highlight line_num
        }
    end
    def fill_to_length line_num
        @data.highlight_cache << nil until @data.highlight_cache.length >= line_num
    end
    def update_status_bar_highlight_progress
        status_bar = @data.app.widgets.detect { |sb| (sb.is_a? StatusBar) and (sb.buffer == self) }
        return if status_bar.nil? # minor hack - FIXME
        hl_len = [@data.highlight_cache.compact.length, @data.lines.length].min
        done_ratio = (hl_len / @data.lines.length.to_f)
        status_bar.highlight_progress = (done_ratio >= 1) ? nil : done_ratio
=begin
        status_bar.render 0
        @data.app.refresh_widgets
        @data.app.display_cursor self
=end
    end
    def _invalidate_line_highlight line_num
        raise if line_num.nil?
        fill_to_length line_num
        @data.highlight_cache[line_num] = nil
        update_status_bar_highlight_progress unless $test_case # hack-ish!
    end
    def ensure_line_highlight y
        fill_to_length y
        pos_of_first_nil = @data.highlight_cache.index nil
        found = !pos_of_first_nil.nil?
        dbg(:dbg_highlight) { "ensure_line_highlight #{y}" }
        dbg(:hl) { "#{y} -- #{@data.highlight_cache[y].inspect} :: #{@data.lines[y].inspect}" }
        if (found and pos_of_first_nil <= y) or @data.highlight_cache[y].nil?
            pos_of_first_nil = [y, @data.highlight_cache.length].min
            # TODO - can become complex when we have multiple points of modification inside the visible screen
            (pos_of_first_nil..y).each {
               |line_num|
               tags = []
               dbg(:dbg_highlight) { "rehighlighting #{line_num}! - \"#{@data.lines[line_num]}\" from [(#{@data.lines.inspect})]" }
               state = @data.highlighter.get_highlight_state self, line_num
               @data.lines_highlighted << line_num
               @data.highlighter.highlight_line(self, @data.lines[line_num], line_num) {
                  |color, bold, word|
                  tags << [color, bold, word]
               }
               @data.highlight_cache[line_num] = tags
               break unless (@data.highlighter.should_continue_highlight_pass? self, line_num, state)
               update_status_bar_highlight_progress unless $test_case # hack-ish!
            }
            raise "failed to highlight requested line #{y}!" if @data.highlight_cache[y].nil?
            @data.highlight_cache[y+1] = nil
        end
    end
    def iterate_line_highlight y, line = nil
        if line.nil?
            if y > last_line_num
               yield Curses::COLOR_WHITE, false, " "
            else
            ensure_line_highlight y
yield Curses::COLOR_WHITE, false, @data.lines[y]
return
            @data.highlight_cache[y].each { 
                |color, bold, word|
                yield color, bold, word
            }
            end
        else
            @data.highlighter.highlight_line(self, line, y) {
                |color, bold, word|
#               yield color, bold, word
            }
yield Curses::COLOR_WHITE, false, line
return
        end
    end
    def last_line_num
        @data.lines.empty? ? 0 : @data.lines.length - 1
    end
    def last_char_on_line y
        raise "invalid y == #{y}" if last_line_num > @data.lines.length
        @data.lines[y].empty? ? 0 : @data.lines[y].length - 1
    end
    def make_copy
        self.class.new @data.app, nil, @data
    end
    def initialize app, lines = BufferLineArray.new, data = nil
        if data.nil?
            @data = BufferData.new
            @data.highlight_cache = []
            @data.needs_redraw = false
        end
        @got_a_scroll_already = false
        @need_to_scroll = 0
        if data.nil?
            @data.redraw_list = []
            @data.app = app
            @data.lines = lines
            @data.fname = nil
        end
        @top   = 0
        @x, @y = 0, 0
        if data.nil?
            @data.lines_highlighted = []
            @data.fake_buffer = false
            @data.hlstacks, @data.classstacks, @data.tokens = [], [], []
            @data.dlog = EditorApp::DiffLogger::DifferenceLog.new app, self
            @data.is_paste_buffer = false
        end
        if !data.nil?
            @data = data
        end
        update_highlighter
        BufferListing::instance << self
        app.change_listeners << self.method(:notified_of_change)
    end
    def update_highlighter
        hls = Highlighters::instance.registered_highlighters.sort_by { |plugin| -plugin.importance }
        hl_class = hls.detect { |hler| hler.can_highlight? self }
        @data.highlighter = hl_class.nil? ? nil : hl_class.new
    end
    def fname= val
        @data.fname = val
        update_highlighter
    end
    def extend_array_to_num arr, num
        diff = (num - arr.length)
        diff.times { arr << nil } if diff > 0
    end
    def notified_of_change change, direction
        # TODO - optimisation: ability to cancel background thread by merging the two requests somehow
        sign = direction ? 1 : -1
        # return unless @data.highlighter.class.has_structure?
        if !change.is_a? EditorApp::DiffLogger::CursorPositionChange
            extend_array_to_num @data.hlstacks, change.line_num
            extend_array_to_num @data.classstacks, change.line_num
            extend_array_to_num @data.highlight_cache, change.line_num
        end
        case change
        when EditorApp::DiffLogger::InsertLineAfterChange
            if direction
                @data.hlstacks.insert_after change.line_num, nil
                @data.classstacks.insert_after change.line_num, nil
                @data.highlight_cache.insert_after change.line_num, nil
            else
                @data.hlstacks.delete_at change.line_num
                @data.classstacks.delete_at change.line_num
                @data.highlight_cache.delete_at change.line_num
            end
            # we invalidate the next line as thats where we insert
            invalidate_line_highlight change.line_num + 1
        when EditorApp::DiffLogger::RemoveLineChange
            if direction
                @data.hlstacks.insert_after change.line_num, nil
                @data.classstacks.insert_after change.line_num, nil
                @data.highlight_cache.insert_after change.line_num, nil
            else
                @data.hlstacks.delete_at change.line_num
                @data.classstacks.delete_at change.line_num
                @data.highlight_cache.delete_at change.line_num
            end
            # we invalidate the current line - note - what about removal of the last line in a document
            invalidate_line_highlight change.line_num
        when EditorApp::DiffLogger::ModifyLineChange 
            invalidate_line_highlight change.line_num
        when EditorApp::DiffLogger::CursorPositionChange
            ;
        else
            raise "unhandled change type!! #{change.type}"
        end
    end
    def x= pos
        @data.app.end_char_mode = false
        @x = pos
    end
    def move_to x, y
        buffer = self
        buffer.x = x
        if y < buffer.top
            @data.app.scroll_up(buffer)   until @data.app.line_displayed?(buffer, y)
        elsif y >= (buffer.top + @data.app.screen_height)
            @data.app.scroll_down(buffer) until @data.app.line_displayed?(buffer, y)
        end
        buffer.y = y
    end
    def move_to_x x
        buffer = self
        move_to x, buffer.y
    end
    def move_to_y y
        buffer = self
        move_to buffer.x, y
    end
    def out_of_bounds y, x
        (x >= @data.lines[y].length)
    end
    # TODO god this logic is ugly
    def out_of_bounds2 y, x
        (x > @data.lines[y].length)
    end
    def text
       (@data.lines.join "\n")
    end
end

end

