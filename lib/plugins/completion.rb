module Ruvi
    module Completion
        class FilenameCompleter
            def initialize app
                @app = app
                @app.add_command_binding("\C-x\C-f") { 
                    buffer = @app.current_buffer
                    current_line = buffer.lines[buffer.y]
                    filename = nil
                    idx = -1
                    while true
                        idx = current_line.index "/", idx + 1
                        return if idx.nil?
                        filename = current_line[idx..buffer.x]
                        break if File.exists? File.dirname(filename)
                    end
                    to_insert = Dir[filename+"*"].first.slice filename.length..-1
                    EditorApp::DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                        buffer.lines[buffer.y][buffer.ax, 0] = to_insert
                        EditorApp.invalidate_buffer_line buffer, buffer.y
                    }
                    buffer.x += to_insert.length
                }
            end
        end
        class WordCompleter
            def initialize app
                @app = app
                @app.add_insert_binding("\C-n") { do_completion }
                @app.change_listeners << self.method(:notify_of_change)
                @changes = []
                @buffer_blub = {}
            end
            def notify_of_change change, direction
                @changes << [change, direction]
            end
            def process_line buffer, line, num
                word_list = []
                buffer.iterate_line_highlight(num, line) {
                    |k|
                    if buffer.highlighter.is_a? PlainTextHighlighter
                        word_list += line.split(/([,| ])/)
                    else
                        word_list << k
                    end
                }
                word_list
            end
            def add_word_list buffer, word_list, diff
                word_list.each {
                    |word|
                    @buffer_blub[buffer][word] += diff
                }
            end
            def process_changes buffer
                if !(@buffer_blub.has_key? buffer)
                    @buffer_blub[buffer] = Hash.new { 0 }
                    (0...buffer.lines.length).each {
                        |num|
                        word_list = process_line buffer, buffer.lines[num], num
                        add_word_list buffer, word_list, 1
                    }
                else
                    @buffer_blub[buffer] = Hash.new { 0 }
                    @changes.each {
                        |mod_with_direction|
                        change, direction = *mod_with_direction
                        sign = direction ? 1 : -1
                        case change
                        when EditorApp::DiffLogger::InsertLineAfterChange
                            word_list = process_line buffer, change.new_line_data, change.line_num
                            add_word_list buffer, word_list, sign * 1
                        when EditorApp::DiffLogger::RemoveLineChange
                            word_list = process_line buffer, change.old_line_data, change.line_num
                            add_word_list buffer, word_list, sign * -1
                        when EditorApp::DiffLogger::ModifyLineChange 
                            word_list = process_line buffer, change.old_line_data, change.line_num
                            add_word_list buffer, word_list, sign * -1
                            word_list = process_line buffer, change.new_line_data, change.line_num
                            add_word_list buffer, word_list, sign * 1
                        else
                            raise "unhandled change type!! #{change.type}"
                        end
                    }
                    @app.status_bar_edit_line "would process completion! got #{@changes.length} changes!"
                    @changes = []
                end
            end
            def do_completion
                buffer = @app.current_buffer
                process_changes buffer
                word_list = process_line buffer, buffer.lines[buffer.y], buffer.y
                curx = 0
                token = word_list.find { 
                            |tok| 
                            a = (tok == word_list.last) || (curx > buffer.x)
                            curx += tok.length
                            a
                        }
                possibles = @buffer_blub[buffer].keys
                possibles.delete token
                options = possibles.find_all { |possible| possible.index(token) == 0 or token.empty? }
                sorted_options = options.sort_by { |val| -@buffer_blub[buffer][val] }
                if sorted_options.empty?
                    @app.status_bar_edit_line "Sorry, no completion found!"
                    return
                end
                to_insert = sorted_options.first.slice(token.length..-1)
                EditorApp::DiffLogger::ModifyLineChange.new(buffer, buffer.y) {
                    buffer.lines[buffer.y][buffer.ax, 0] = to_insert
                    EditorApp.invalidate_buffer_line buffer, buffer.y
                }
                ecm = @app.end_char_mode
                buffer.x += to_insert.length
                @app.end_char_mode = ecm
            end
        end
    end
end
