require "debug.rb"

module Ruvi

class EditorApp

    # widgets don't have children. widgets have parents

    # each status bar    has a parent of the status bar vbox
    # status bar vbox    has a parent of the root
    # ruler sub window   has a parent of the main window hbox
    # actual edit window has a parent of the main window hbox
    # main window hbox   has a parent of the root
    
    # ruler sub window has a height of 10
    # actual edit window is the only window left in that hbox so it querys up the tree for other static usages
    # no other items further up in the tree require space so it gets the full width
    
    # each status bar uses up 1 line height wise
    # the remaining main window hbox gets the remaining space
    
    def self.perform_layout
        scr = WinDescs::instance.stdscr
        WinDescs::instance.descs.clear
        @@app.blub # TODO rename
    end

    def final_widget_size widget
        # !FIXME! - this is crap and hardcoded - !FIXME!
        docviews = @widgets.find_all { |w| w.is_a? DocView }
        number_of_horiz_splits = docviews.length
        status_bars = @widgets.find_all { |w| w.is_a? StatusBar }
        total_size_status_bars = status_bars.inject(0) { |sum, item| sum += item.height }
        rulers = @widgets.find_all { |w| w.is_a? Ruler }
        first_size_ruler = rulers.empty? ? 0 : rulers.first.width
        sx, sy = WinDescs::instance.stdscr.maxx, WinDescs::instance.stdscr.maxy
        case widget
        when @doc_with_ruler, @doc_with_ruler2
            children = @widgets.find_all { |w| w.parent == widget }
            dx, dy = nil, nil
            if widget.is_a? HBox
                dx = children.inject(0) { |sum, w| sum += final_widget_size(w)[0] }
                # we assume that all the widths will be the same... maybe we should assert?
                dy = final_widget_size(children.first)[1]
            else
                # we assume that all the heights will be the same... maybe we should assert?
                dx = final_widget_size(children.first)[0]
                dy = children.inject(0) { |sum, w| sum += final_widget_size(w)[1] }
            end
            return [dx, dy]
        when Ruler
            return [first_size_ruler, (sy - total_size_status_bars) / number_of_horiz_splits]
        when DocView
            return [sx - first_size_ruler, (sy - total_size_status_bars) / number_of_horiz_splits]
        when StatusBar
            # we no parent and we are width.is_nil therefore we use the entire width
            # we have .height.is_not_nil so we take this height
            return [sx, widget.height]
        end
        raise "oops"
    end

    def final_widget_position widget
        last_parent = widget
        current_box = widget.parent
        offset_x, offset_y = 0, 0
        while !current_box.nil?
            idx = @widgets.index last_parent
            raise "blub?" if !current_box.is_a? VBox and !current_box.is_a? HBox
            children = @widgets.slice(0...idx).find_all { |w| w.parent == current_box }
            if current_box.is_a? HBox
                size = children.inject(0) { |sum, w| sum += final_widget_size(w)[0] }
                offset_x += size
            else
                size = children.inject(0) { |sum, w| sum += final_widget_size(w)[1] }
                offset_y += size
            end
            last_parent = current_box
            current_box = current_box.parent
        end
        [offset_x, offset_y]
    end

    def blah maxx, maxy # TODO
        @widgets.each { 
            |w|
            next if w.kind_of? Box
            desc = WinDesc.new(*(final_widget_position(w) + final_widget_size(w)))
                WinDescs::instance.descs[w] = desc
        }
    end

    def blub # TODO
        return if @root.nil?
        stdscr = WinDescs::instance.stdscr
        blah stdscr.maxx, stdscr.maxy
        @needs_full_redraw = true
    end

end

class Widget
    attr_accessor :buffer, :parent, :cursor
    def initialize app, buffer
        @app, @buffer = app, buffer
        @cursor = Point.new 0, 0
        @parent = nil
    end
    def width
        raise "width must be implemented in sub classes!"
    end
    def height
        raise "height must be implemented in sub classes!"
    end
    def watch_buffer
        nil
    end
end

class Box < Widget
    def initialize app, parent
        @app, @parent = app, parent
        @buffer = nil # TODO - lets remove this from widget, its silllyyyy
    end
    def width;  nil; end
    def height; nil; end
end

class HBox < Box; end
class VBox < Box; end

class StatusBar < Widget
    attr_reader :text, :needs_update
    attr_writer :highlight_progress
    def initialize app, buffer
        super app, buffer
        @text = ""
        @highlight_progress = nil
        @needs_update = true
    end
    def highlight_progress= p
        @highlight_progress = p
        invalidate
    end
    def text= val
        @text = val
        invalidate
    end
    def invalidate
        @needs_update = true
    end
    def width;  nil; end
    def height; 1;   end
    def canvas
        Curses.begin_draw WinDescs::instance.descs[self]
    end
    def render y
        return unless @needs_update
        screen = canvas
        current = (@app.current_buffer == @buffer)
        screen.setpos y, 0 # y, x
        hl_prog_str = @highlight_progress.nil? || !current ? "" : "HL:#{"%0.2f" % (@highlight_progress * 100)}% "
        pos_str = ":B(#{@buffer.bnum}:#{@buffer.fname})- #{@buffer.x},#{@buffer.y}:"
        desc_str = hl_prog_str + pos_str 
        max_len = WinDescs::instance.descs[self].sx - 1 - desc_str.length
        fg = current ? Curses::COLOR_RED : Curses::COLOR_CYAN
        screen.set_attr true, fg, Curses::COLOR_BLACK
        str = current ? @text[0, max_len].ljust(max_len) : (" " * max_len)
        screen.addstr str + desc_str
        @needs_update = false
    end
end

class Ruler < Widget
    def canvas
        Curses.begin_draw WinDescs::instance.descs[self]
    end
    def width;  10;  end
    def height; nil; end
    def watch_buffer
        @buffer
    end
    def render y
        screen = canvas
        screen.setpos y, 0 # y, x
        screen.set_attr true, Curses::COLOR_WHITE, Curses::COLOR_BLACK
        valid_line = (@buffer.top + y) < @buffer.lines.length
        str = valid_line ? "#{@buffer.top + y}" : ""
        screen.addstr str.rjust(screen.maxx - 2)
    end
end

class DocView < Widget
    HLSpan = Struct.new :color, :bgcolor, :bold, :text
    BGC_NORMAL  = Curses::COLOR_BLACK
    attr_accessor :absolute_cursor
    def initialize *k
        super(*k)
        @absolute_cursor = Point.new 0, 0
    end
    def width;  nil; end
    def height; nil; end
    def watch_buffer
        @buffer
    end
    def bg_spans_for_selection_at_y selc, y, line, hilite_colour, width
        line_filler = [HLSpan.new(Curses::COLOR_WHITE, BGC_NORMAL, true, " " * (width - 1))]
        return line_filler if selc.nil? || selc.invalid?
        selc = selc.right_way_up
        hlls = EditorApp.lineslice_for_selection_intersect_with_y selc, y, line.length
        return line_filler if hlls.nil?
        temp_str = line.dup + (" " * [hlls.x2 - line.length, 0].max)
        bg_spans = []
        bg_spans << HLSpan.new(Curses::COLOR_WHITE, BGC_NORMAL,    true, temp_str.slice!(0, hlls.x1) || "")
        bg_spans << HLSpan.new(Curses::COLOR_WHITE, hilite_colour, true, temp_str.slice!(0, hlls.x2 - hlls.x1) || "")
        bg_spans << HLSpan.new(Curses::COLOR_WHITE, BGC_NORMAL,    true, temp_str || "")
        visual_selc_after_end = (selc.mode == :selc_lined)
        needed = ((width - 1) - line.length)
        needed = 0 if needed < 0
        bg_spans << HLSpan.new(Curses::COLOR_WHITE, (visual_selc_after_end ? hilite_colour : BGC_NORMAL), true, " " * needed)
    end
    def normalize_span_lengths spans1, spans2 # overlays spans1 lengths over spans2, thusly extras in spans2 are discarded
        tmp_spans1, tmp_spans2 = [], []
        while true
            span1, span2 = spans1.first, spans2.first
            break if (span1.nil? and span2.nil?) or (span1.nil?)
            if span2.nil?
                dbg(:dbg_render) { "render argh!!!!" }
                break
            end
            if  span1.text.length < span2.text.length
                span2 = span2.dup
                span2.text = spans2.first.text.slice!(0, span1.text.length)
                spans1.shift
            elsif span1.text.length > span2.text.length
                # test - TODO - when does this happen?
                span1 = span1.dup
                span1.text = spans1.first.text.slice!(0, span2.text.length)
                spans2.shift
            else
                spans2.shift
                spans1.shift
            end
            tmp_spans1 << span1
            tmp_spans2 << span2
        end
        return tmp_spans1, tmp_spans2
    end
    def merge_bgspans_with_spans merged_spans, hl_bg_spans
        normalized_merged_spans, normalized_hl_bg_spans = normalize_span_lengths merged_spans, hl_bg_spans
        
        hl_merged_spans = []
        normalized_hl_bg_spans.zip(normalized_merged_spans) {
            |b,a| 
            c = a.dup
            c.bgcolor = b.bgcolor if c.bgcolor == BGC_NORMAL
            hl_merged_spans << c
        }
        
        hl_merged_spans 
    end
    def canvas
        Curses.begin_draw WinDescs::instance.descs[self]
    end
    def render y
        a_tab = " " * @app.config_get_tab_size
        buf = @buffer
        width = WinDescs::instance.descs[self].sx
        line = buf.lines[buf.top + y]
        # TODO render empty lines..
        line = "" if line.nil?
        spans = []
        if buf.is_paste_buffer
            # test - switch to paste buffer - needs a render check really...
            linetype = (line.newline_at_start ? "S" : "-") + (line.newline_at_end ? "E" : "-") + ":"
            spans << HLSpan.new(Curses::COLOR_YELLOW, BGC_NORMAL, true, linetype)
        end
        
        xpos = 0
        max_len = width - 1
        # TODO - test the expanded_str stuff
        # FIXME  a final half off screen tab will be rendered incorrectly atm
        buf.iterate_line_highlight(buf.top+y) {
            |color, bold, word|
            str = word.to_str.dup
            expanded_str = str.gsub("\t", a_tab)
            overend = ((xpos + expanded_str.length) >= max_len)
            if overend and (xpos <= max_len)
                expanded_str = expanded_str.slice 0, max_len
            elsif overend
                next
            end
            spans << HLSpan.new(color, BGC_NORMAL, bold, str)
            xpos += expanded_str.length
        }
        
        if max_len > xpos or spans.empty?
            len = (max_len - xpos)
            len = 0 if len < 0
            spans << HLSpan.new(Curses::COLOR_WHITE, BGC_NORMAL, false, " " * len)
        end

        merged_spans = spans
        
        if !@app.selection.nil?
            bg_spans = bg_spans_for_selection_at_y @app.selection, buf.top+y, line, Curses::COLOR_YELLOW, width
            merged_spans = merge_bgspans_with_spans merged_spans, bg_spans.dup
        end
        
        if !@app.hl_selection.nil?
            hl_bg_spans = bg_spans_for_selection_at_y @app.hl_selection, buf.top+y, line, Curses::COLOR_BLUE, width
            merged_spans = merge_bgspans_with_spans merged_spans, hl_bg_spans
        end
        
        cx, cy = @absolute_cursor.x, @absolute_cursor.y + buf.top
        if cy == (y + buf.top)
            cursor_selection = Selection.new Point.new(cx, cy), Point.new(cx, cy), :selc_normal
            curs_spans = bg_spans_for_selection_at_y cursor_selection, buf.top+y, line, Curses::COLOR_GREEN, width
            merged_spans = merge_bgspans_with_spans merged_spans, curs_spans
        end
        
        screen = canvas
        screen.setpos y, 0 # y, x
        merged_spans.each {
            |span|
            next if span.text.nil?
            screen.set_attr span.bold, span.color, span.bgcolor
            screen.addstr span.text.gsub("\t", a_tab)
        }
    end
end

end
