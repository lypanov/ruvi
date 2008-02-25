require "debug.rb"

module Ruvi

  class EditorApp

    module DiffLogger

    class DifferenceLog
        attr_reader :partial_flush_mode
        def initialize app, buffer
            # history_buffer used from here via indirection, as maybe history_buffer can change?
            @app, @buffer = app, buffer
            @last_save_point, @current_patch_num = nil, nil
            @diffs = []
            @ids2changesets = {}
            @partial_flush_mode = false
        end
        def difflog_fname
            if !@buffer.fname.nil?
                fname = "#{File.dirname @buffer.fname}#{File::SEPARATOR}+#{File.basename @buffer.fname}.edlog"
                return fname if File.writable? fname
            end
            dir = $win32 ? "#{ENV["TEMP"]}" : "/tmp/"
            "#{dir}#{$$}.#{(0..8).collect{rand 10}.join ""}.edlog"
        end
        def logline line
            dbg(:ufw) { line }
            @app.history_buffer.lines << line
            @file = File.open @filename, "w+" if @file.nil?
            @file.puts line
            @file.flush
            @file.fsync
        end
        def finalize
            @file.close unless @file.nil? or @file_closed
            @file_closed = true
        end
        def saved
            flush # not sure about this...
            logline "SAVE_POINT"
            @last_save_point = @current_patch_num
        end
        def branch_id id
            id = (id || "")
            num = 1
            while true
                new_id = "#{id}##{num}"
                num += 1
                break unless @ids2changesets.keys.detect { |_id| _id.index(new_id) == 0 }
            end
            "#{new_id}.1"
        end
        def inc_id id
            return "#1.1" if id.nil?
            raise "invalid id" if id == "1" or id.empty?
            id =~ /^(.*?)([0-9]+)$/
            "#{$1}#{$2.to_i + 1}"
        end
        # goes up branches!
        def prev_id id
            raise "invalid id" if id == "1" or id.empty?
            id =~ /^(.*?)([0-9]+)$/
            if $2 == "1"
                id = id.gsub(/#\d+\.\d+$/, '')
                id = nil if id.empty?
            else
                id = "#{$1}#{$2.to_i - 1}"
            end
            id
        end
        def undo
            return if @current_patch_num.nil?
            change_set = @ids2changesets[@current_patch_num]
            change_set.reverse.each {
                |change| 
                change.undo
            }
            logline "UNDO_CHANGESET #{@current_patch_num}"
            @current_patch_num = prev_id @current_patch_num
        end
        def redo # not really redo... but go forward
            if !@ids2changesets.has_key? inc_id(@current_patch_num)
                return
            end
            if @ids2changesets.keys.find_all { |id| @current_patch_num.nil? || (id.index(@current_patch_num) == 0) }
                last_id = nil
                id = @last_followed_branch
                while true
                    last_id = id
                    id = prev_id id
                    break if id == @current_patch_num or id.nil?
                end
                @current_patch_num = last_id
            else
                @current_patch_num = inc_id @current_patch_num
            end
            logline "REDO_CHANGESET #{@current_patch_num}"
            change_set = @ids2changesets[@current_patch_num]
            change_set.each {
                |change| 
                change.redo
            }
        end
        def do_flush mods
            mods.each {
                |diff|
                logline diff.to_s
            }
        end
        def flush
            return partial_flush if @partial_flush_mode
            start_val = 0
            if !@partial_flush_last_count.nil?
                start_val = @partial_flush_last_count
                @partial_flush_last_count = nil
            end
            return if @diffs.empty?
            do_flush @diffs.slice(start_val..-1)
            if @ids2changesets.has_key? inc_id(@current_patch_num)
                @current_patch_num = branch_id @current_patch_num
            else
                @current_patch_num = inc_id @current_patch_num
            end
            @last_followed_branch = @current_patch_num
            logline "FLUSHED_CHANGESET #{@current_patch_num}"
            @ids2changesets[@current_patch_num] = @diffs
            @diffs = []
        end
        def partial_flush
            new_count = @diffs.length
            mods = @diffs.slice(@partial_flush_last_count..new_count)
            @partial_flush_last_count = new_count
            do_flush mods
        end
        def invalidated?
            # note - patch numbers can never be 0!, nil is used to indicate this!
            # p "(#{@current_patch_num.inspect}) > (#{@last_save_point.inspect}) -> #{(@current_patch_num || "0") > (@last_save_point || "0")}"
            if @current_patch_num == "#1.1" and @last_save_point.nil?
                return true
            else
                return ((@current_patch_num || "#1.1") != (@last_save_point || "#1.1"))
            end
        end
        # log file must always be appended to. all writes are thusly as good as atomic
        # truncate is not available on windows platform afaik
        # is file move atomic on windows platform?
        def load_or_create_difflog
            @filename = difflog_fname
            return load_difflog if File.exists? difflog_fname and $load_difflogs
            @current_patch_num = nil
            @file = nil
        end
        # @current_patch_num is always either nil, or the patch just applied
        def load_difflog
            @ids2changesets = {}
            toreplay = []
            @last_followed_branch = nil
            @file = File.open difflog_fname, "r+"
            @file.each_line {
                |l| 
                matched_type = nil
                DifferenceTypes::instance.registered_change_types.each {
                    |difftype| 
                    matched_type = difftype if difftype.it_was_me l
                }
                if matched_type.nil?
                    case l
                    when /^SAVE_POINT$/
                        @last_save_point = @current_patch_num || "1"
                        toreplay = []
                    when /^FLUSHED_CHANGESET (.*?)$/
                        @last_followed_branch = $1
                        @current_patch_num = $1
                        @ids2changesets[$1] = @diffs
                        @diffs = []
                        toreplay << [:patch, $1]
                    when /^UNDO_CHANGESET (.*?)$/
                        @current_patch_num = prev_id $1
                        toreplay << [:undo, $1]
                    when /^REDO_CHANGESET (.*?)$/
                        @current_patch_num = $1
                        toreplay << [:redo, $1]
                    when /^REVERTED$/
                        ; # pass
                    else
                        raise "line unparseable! - #{l}"
                    end
                else
                    matched_type.from_s(@buffer, l) # auto adds via <<
                end
            }
            dbg(:ufw) { "position count == #{@current_patch_num.inspect} - can be nil if we undo the first patch" }
            dbg(:ufw) { "save point == #{@last_save_point}" }
            
            # in order to flush partial changesets with a missing boundry we force one extra final flush
            if !@diffs.empty?
                flush
                toreplay << [:patch, @current_patch_num]
            end
            
            sets_to_remove = @ids2changesets.index(@last_save_point)
            
            # test - save once, then close file without a save point and force a replay??
            if !@diffs.empty?
                @change_sets.push @diffs
                @diffs = []
            end
            
            dbg(:ufw) { toreplay.inspect }
            
            needs_patch = false
            toreplay.each_with_index {
                |tuple, idx| 
                cmd, id = *tuple
                dbg(:ufw) { "working on command :: #{cmd} :: #{id}" }
                case cmd
                when :undo
                    dbg(:ufw) { "undoing previous change set" }
                    change_set = @ids2changesets[id]
                    change_set.reverse.each {
                        |change|
                        change.undo
                    }
                    @current_patch_num = prev_id id
                when :redo
                    dbg(:ufw) { "redoing previous change set" }
                    # TODO - test
                    change_set = @ids2changesets[id]
                    change_set.each {
                        |change|
                        change.redo
                    }
                    @current_patch_num = id
                when :patch
                    dbg(:ufw) { "replaying current change set (calls :redo)" }
                    # duplication from below, which in turn is ...
                    dbg(:ufw) { "redoing previous change set" }
                    # duplication from .redo
                    change_set = @ids2changesets[id]
                    change_set.each {
                        |change|
                        change.redo
                        dbg(:ufw) { "\nPLAYING!!! <<<" }
                        dbg(:ufw) { change.to_s }
                        dbg(:ufw) { ">>>\n" }
                    }
                    @current_patch_num = id
                end
            }

        dbg(:ufw) { "current_patch_num state at end of the log replay is #{@current_patch_num.inspect}" }
        end
        def revert_to_save_point
            catch(:waza) {
                while true
                    dbg(:ufw) { "revert_to_save_point - last save point == #{@last_save_point.inspect} : section count == #{@current_patch_num.inspect}" }
                    self.undo
                    # TODO - test - the above happens when there is a edlog, but no file...
                    throw(:waza) if (@current_patch_num == @last_save_point) or (@last_save_point == "1" and @current_patch_num.nil?)

                end
            }
            # maybe this should be distinct from undo???
            logline "REVERTED"
            saved
        end
        def << diff
            @diffs << diff
        end
        def partial_flush_mode= val
            @partial_flush_mode = val
            @partial_flush_last_count = 0 if val
        end
    end

    class DifferenceTypes
        include Singleton
        attr_accessor :registered_change_types
        def initialize
            @registered_change_types = []
        end
        def register_change_type change
            @registered_change_types << change
        end
    end

    class Difference
        attr_accessor :old_cursor, :new_cursor
        # note - line_num.nil? -> generated via *Difference.from_s
        def initialize buffer, line_num = nil
            @buffer = buffer
            @old_cursor, @new_cursor = nil, nil
            if line_num.nil?
                yield self
                @buffer.dlog << self
            else
                dbg(:ufw) { "a #{self.type.inspect} was new'ed" }
                @line_num = line_num
                pre_mod_callback
                yield # must provide a constructor block, for before and after data to be picked up
                post_mod_callback
                @buffer.dlog << self
                notify_of_play
            end
        end
        def notify_of_play
            @buffer.app.change_listeners.each {
               |listener|
               listener.call self, true
            }
        end
        def notify_of_unplay
            @buffer.app.change_listeners.each {
               |listener|
               listener.call self, false
            }
        end
        def finalize
            # test - TODO - no idea...
            @buffer.dlog.finalize
        end
        def pre_mod_callback
            @old_cursor = Point.new(@buffer.x, @buffer.y)
        end
        def post_mod_callback
            @new_cursor = Point.new(@buffer.x, @buffer.y)
        end
        def correct_cursor_position
            # HACK - its possible that we went out of buffer!
            #        until we have made a method for making checks
            #        on the current position in the buffer and the 
            #        stored time_machine cursor position. then we
            #        should keep this workaround *just in case*
            if @buffer.y > @buffer.last_line_num
                @buffer.y = @buffer.last_line_num
            end
        end
        def undo
            notify_of_play
            @buffer.move_to @old_cursor.x, @old_cursor.y
            correct_cursor_position
        end
        def redo
            notify_of_unplay
            @buffer.move_to @new_cursor.x, @new_cursor.y
            correct_cursor_position
        end
        def Difference.transition_regexp
            point_re = /\((.*?),(.*?)\)/
            /\[#{point_re }->#{point_re}]/
        end
        def cursor_transition
            "(#{@old_cursor.x},#{@old_cursor.y})->(#{@new_cursor.x},#{@new_cursor.y})"
        end
        def Difference.inherited sub
            DifferenceTypes::instance.register_change_type sub
        end
    end

    class InsertLineAfterChange < Difference
        attr_accessor :line_num, :new_line_data
        def InsertLineAfterChange.from_s buf, str
            t = self.new(buf) {
                |t|
                str =~ /^INSERT_AFTER:#{transition_regexp}:(.*?):(.*?)$/
                t.old_cursor, t.new_cursor = Point.new($1.to_i, $2.to_i), Point.new($3.to_i, $4.to_i)
                t.line_num, t.new_line_data = $5.to_i, $6
            }
            t 
        end
        def InsertLineAfterChange.it_was_me msg
            msg =~ /^INSERT_AFTER:/
        end
        def post_mod_callback
            super
            @new_line_data = @buffer.lines[@line_num].dup
        end
        def undo
            @buffer.lines.delete_at @line_num
            super
        end
        def redo
            @buffer.lines.insert_after @line_num, @new_line_data
            super
        end
        def to_s
            "INSERT_AFTER:[#{cursor_transition}]:#{@line_num}:#{@new_line_data}"
        end
    end

    class CursorPositionChange < Difference
        def CursorPositionChange.from_s buf, str
            t = self.new(buf) {
                |t|
                str =~ /^CURSOR_MOVE:#{transition_regexp}$/
                t.old_cursor, t.new_cursor = Point.new($1.to_i, $2.to_i), Point.new($3.to_i, $4.to_i)
            }
            t 
        end
        def CursorPositionChange.it_was_me msg
            msg =~ /^CURSOR_MOVE:/
        end
        def to_s
            "CURSOR_MOVE:[#{cursor_transition}]"
        end
    end

    class ModifyLineChange < Difference
        attr_accessor :line_num, :old_line_data, :new_line_data
        def ModifyLineChange.from_s buf, str
            t = self.new(buf) {
                |t|
                str =~ /^MODIFY:#{transition_regexp}:(.*?):\((.*?)\)=>\((.*?)\)$/
                t.old_cursor, t.new_cursor = Point.new($1.to_i, $2.to_i), Point.new($3.to_i, $4.to_i)
                t.line_num, t.old_line_data, t.new_line_data = $5.to_i, $6, $7
            }
            t
        end
        def ModifyLineChange.it_was_me msg
            msg =~ /^MODIFY:/
        end
        def pre_mod_callback
            super
            @old_line_data = @buffer.lines[@line_num].dup
        end
        def post_mod_callback
            super
            @new_line_data = @buffer.lines[@line_num].dup
        end
        def undo
            @buffer.lines[@line_num] = @old_line_data
            super
        end
        def redo
            @buffer.lines[@line_num] = @new_line_data
            super
        end
        def to_s
            "MODIFY:[#{cursor_transition}]:#{@line_num}:(#{@old_line_data})=>(#{@new_line_data})"
        end
    end

    class RemoveLineChange < Difference
        attr_accessor :line_num, :old_line_data
        def pre_mod_callback
            super
            @old_line_data = @buffer.lines[@line_num].dup
        end
        def RemoveLineChange.from_s buf, str
            t = self.new(buf) {
                |t|
                str =~ /^REMOVE:#{transition_regexp}:(.*?):(.*?)$/
                t.old_cursor, t.new_cursor = Point.new($1.to_i, $2.to_i), Point.new($3.to_i, $4.to_i)
                t.line_num, t.old_line_data = $5.to_i, $6
            }
            t
        end
        def RemoveLineChange.it_was_me msg
            msg =~ /^REMOVE:/
        end
        def undo
            @buffer.lines.insert_after @line_num, @old_line_data
            super
        end
        def redo
            @buffer.lines.delete_at @line_num
            super
        end
        def to_s
            "REMOVE:[#{cursor_transition}]:#{@line_num}:#{@old_line_data}"
        end
    end
    
 end
 end

 end
