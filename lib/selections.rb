require "misc.rb"

module Ruvi

LineSlice = Struct.new :x1, :x2, :y
class LineSlice
   include NewLineAttributes
   def to_s
       "#{y}:#{x1}-#{x2}#{newline_at_start ? "S" : ""}#{newline_at_end ? "E" : ""}"
   end
end

class Selection
    attr_accessor :s, :e
    attr_accessor :mode
    def initialize s = Point.new, e = Point.new, mode = nil
        @mode = mode
        @s, @e = s, e
    end
    def invalid?
        self.s.nil? || self.e.nil?
    end
    def reverse
        mydup = self.dup
        tmp = mydup.s
        mydup.s = mydup.e
        mydup.e = tmp
        mydup
    end
    def right_way_up
        raise "right_way_up called for selection with nil s" if @s.nil?
        raise "right_way_up called for selection with nil e" if @e.nil?
        (@e > @s) ? self : reverse
    end
end

class EditorApp

    ###########################
    # SELECTION RELATED STUFF #
    ###########################

    def make_selection_exclusive_given_current_position buffer, selc
        pos = Point.new(buffer.x, buffer.y)
        if selc.e == pos
            selc.e.x = limit_to_positive(selc.e.x - 1)
        elsif selc.s == pos
            selc.s.x = (selc.s.x + 1).clamp_to 0, buffer.last_char_on_line(selc.s.y)
        end
    end
    
# REQUIRES RIGHT WAY UP SELECTION - though it may not appear that is does :)
    def EditorApp.lineslice_for_selection_intersect_with_y selc, currenty, line_len
        selc = selc.dup
        hlls      = LineSlice.new
        hlls.newline_at_start, hlls.newline_at_end = false, false
        hlls.y    = currenty
        lined     = (selc.mode == :selc_lined)
        box       = (selc.mode == :selc_boxed)
        multiline = (selc.e.y != selc.s.y)
        end_char_mode = (EditorApp::app_instance.end_char_mode and selc.s != selc.e)
        sorted_x_1, sorted_x_2 = *([selc.s.x, selc.e.x].sort)
        if not (((selc.s.y)..(selc.e.y)) === currenty)
            return nil
        elsif multiline and currenty == selc.s.y and !box
            # first line in selection
            hlls.x1 = lined ? 0 : sorted_x_1
            hlls.x2 = line_len
            hlls.newline_at_start = lined
            hlls.newline_at_end   = true
        elsif multiline and currenty == selc.e.y and !box
            # end line of selection, if in end_char_mode we wish to join with next line
            # to indicate a join, we want start + !end - app.end_char_mode
            # TODO - clean up the boolean logic!!!
            if lined
                hlls.newline_at_end   = lined
                hlls.newline_at_start = true
            elsif end_char_mode
                hlls.newline_at_end   = false
                hlls.newline_at_start = true
            else
                hlls.newline_at_end   = false
                hlls.newline_at_start = false
            end
            hlls.x1 = 0
            hlls.x2 = lined ? line_len : sorted_x_2
        elsif !multiline and currenty == selc.s.y and !box # implicit: and currenty == selc.e.y # "!=" surely???
            # single line selection - if its end_char_mode we wish to join to next line
            hlls.newline_at_end   = (lined || end_char_mode)
            hlls.newline_at_start = lined
            hlls.x1 = lined ? 0 : sorted_x_1
            hlls.x2 = lined ? line_len : sorted_x_2
        else
            hlls.newline_at_end   = !box
            hlls.newline_at_start = !box
            hlls.x1 = box ? sorted_x_1 : 0
            hlls.x2 = box ? sorted_x_2 : line_len
        end
        hlls.x2 += 1
        return hlls
    end
    
# USES right_way_up
    def update_selection buffer
        EditorApp.each_lineslice_in_selection(buffer, @last_selection) {
            |hlls| 
            EditorApp.invalidate_buffer_line buffer, hlls.y
        } unless @last_selection.nil?
        
        no_selection = @selection.nil? || @selection.invalid?
        
        EditorApp.each_lineslice_in_selection(buffer, @selection.right_way_up) {
            |hlls| 
            EditorApp.invalidate_buffer_line buffer, hlls.y
        } unless no_selection
        
        @last_selection = no_selection ? nil : @selection.dup.right_way_up
    end

# REQUIRES RIGHT WAY UP SELECTION
    def EditorApp.each_lineslice_in_selection buffer, selc
        ((selc.s.y)..(selc.e.y)).each {
           |currenty| 
           line = buffer.lines[currenty]
           break if currenty >= buffer.lines.length
           yield EditorApp.lineslice_for_selection_intersect_with_y(selc, currenty, line.length)
        }
    end

# USES right_way_up
    def EditorApp.manip_selection buffer, selc, manipulation, paste_buffer
        raise  "manip_selection called for invalid selection object" if selc.invalid?
        paste_lines = BufferLineArray.new
        removed_lines = 0
        selc = selc.right_way_up
        lineslices = []
        EditorApp.each_lineslice_in_selection(buffer, selc) {
            |hlls|
            next if hlls.nil?
            lineslices << hlls
        }
        join_list = []
        lineslices.each_with_index {
            |hlls, index| 
            # NB - !newline_at_start +  newline_at_end == join previous line with this (only at start of a selection)
            #    -  newline_at_start +  newline_at_end == delete entire line
            #    - !newline_at_start + !newline_at_end == just copy/modify entire line
            #    -  newline_at_start + !newline_at_end == join next line with this     (only at end of a selection)
            lbuffer = nil
            case manipulation
            when :manip_cut
                updated_y = hlls.y - removed_lines
                if hlls.newline_at_start and hlls.newline_at_end
                    DiffLogger::RemoveLineChange.new(buffer, updated_y) {
                        lbuffer = BufferLine.new buffer.lines.delete_at(updated_y)
                        removed_lines += 1
                    }
                else
                    DiffLogger::ModifyLineChange.new(buffer, updated_y) {
                        line = buffer.lines[updated_y]
                        lbuffer = BufferLine.new line.slice!((hlls.x1)...(hlls.x2)).dup
                    }
                end
                if !hlls.newline_at_start and hlls.newline_at_end and index == 0
                    join_list << updated_y
                end
                if hlls.newline_at_start and !hlls.newline_at_end and index == (lineslices.length - 1)
                    join_list << updated_y - 1 if updated_y != buffer.lines.length - 1
                end
                EditorApp.invalidate_buffer_line buffer, updated_y
            when :manip_copy
                # test - Vjjy
                lbuffer = BufferLine.new buffer.lines[hlls.y].slice((hlls.x1)...(hlls.x2)).dup
            end
            lbuffer.newline_at_start, lbuffer.newline_at_end = hlls.newline_at_start, hlls.newline_at_end
            paste_lines << lbuffer 
        }
        # now we apply the joins post cut in order to prevent utter confusion
        join_list.each {
            |to_join|
            next if to_join == buffer.lines.length
            EditorApp.join_next_line_onto_this buffer, to_join
        }
        if manipulation == :manip_cut
            if buffer.lines.empty?
                DiffLogger::InsertLineAfterChange.new(buffer, -1) {
                    buffer.lines << (BufferLine.new "") 
                }
            end
            DiffLogger::CursorPositionChange.new(buffer, buffer.y) {
                y = (selc.s.y).clamp_to 0, buffer.last_line_num
                x = (selc.s.x).clamp_to 0, buffer.last_char_on_line(y)
                buffer.move_to x, y
            }
        end
        paste_buffer.lines = paste_lines
    end

    def end_selection buffer
        # test - Vjjy from above should cover this
        @selection_for_last_command = @selection
        @selection = nil
        redraw buffer
    end

end
end
