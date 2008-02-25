begin

require 'rrb/script'
require 'rrb/node'
require 'rrb/completion'
require 'rrb/rename_local_var'
require 'rrb/rename_instance_var'
require 'rrb/rename_class_var'
require 'rrb/rename_global_var'
require 'rrb/rename_method'
require 'rrb/rename_method_all'
require 'rrb/rename_constant'
require 'rrb/extract_method'
require 'rrb/move_method'
require 'rrb/pullup_method'
require 'rrb/pushdown_method'
require 'rrb/remove_parameter'
require 'rrb/extract_superclass'
require 'rrb/default_value'

module Ruvi # this is local to this file only for the moment...
    class RRBPlugin
      attr_accessor :app
      def initialize app
        @app = app
        register_command
      end

      def register_command
        @app.setup_cmd(%w{rrb_rename_local_vars rrb_rename_instance_var rrb_rename_class_var rrb_rename_global_var 
                          rrb_rename_constant rrb_extract_method rrb_rename_method rrb_push_down_method 
                          rrb_pull_up_method}.join(","), 
                       /^rrb_/) {
            |ctx|
            case ctx.cmd_line
            when "rrb_rename_local_vars"
                  RenameLocalVariableDialog.new self
            when "rrb_extract_method"
                  ExtractMethodDialog.new self
            when "rrb_rename_instance_var"
                  RenameInstanceVariableDialog.new self
            when "rrb_rename_class_var"
                  RenameClassVariableDialog.new self
            when "rrb_rename_global_var"
                  RenameGlobalVariableDialog.new self
            when "rrb_rename_method"
                  RenameMethodDialog.new self
            when "rrb_rename_constant"
                  RenameConstantDialog.new self
            when "rrb_push_down_method"
                  PushdownMethodDialog.new self
            when "rrb_pull_up_method"
                  PullupMethodDialog.new self
            else
                  fail "sorry, unimplemented!"
            end
        }
      end

    def new_script(plugin)
      script_files = []
      # extend to handle multiple files..
      script_files << ::RRB::ScriptFile.new(plugin.app.current_buffer.lines.join("\n"), plugin.app.current_buffer.fname)
      return ::RRB::Script.new(script_files)
    end

    def rewrite_script(plugin, script)
      script.files.each {
         |script_file|
         if plugin.app.current_buffer.fname == script_file.path
           plugin.app.current_buffer.lines = script_file.new_script.split("\n").collect { |l| BufferLine.new l }
         end
      }
      plugin.app.redraw plugin.app.current_buffer
    end

    class RefactorDialog
      def initialize plugin
        @plugin = plugin
        @app = plugin.app
        @current_buffer = plugin.app.current_buffer
        @cursor_line = plugin.app.current_buffer.y + 1
        @script = plugin.new_script(plugin)
      end
      def do_it
        begin
          if enable_refactor?
            refactor
            @plugin.rewrite_script(@plugin, @script)
          else
            @app.status_bar_edit_line "ERROR : #{@script.error_message}"
          end
        rescue => e
          STDERR.puts e.inspect
          STDERR.puts e.backtrace
          @app.status_bar_edit_line "rrb really screwed up :("
        end
      end
      def enable_refactor? ; end
      def refactor ; end
    end

    class RenameDialog < RefactorDialog
      def initialize plugin
        super plugin
        word_range = plugin.app.get_word_under_cursor plugin.app.current_buffer, :look_for_ruby_variables
        @old_value = plugin.app.current_buffer.lines[plugin.app.current_buffer.y].slice(word_range)
        @txt_new_variable = plugin.app.get_user_input
        do_it
      end
    end

    class RenameLocalVariableDialog < RenameDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        method = @script.get_method_on_cursor(@current_buffer.fname, @cursor_line).name
        method_name = ::RRB::Method[method]
        return [method_name, @old_value, @txt_new_variable]        
      end

      def enable_refactor?
        return @script.rename_local_var?(*setup_args)
      end

      def refactor
        @script.rename_local_var(*setup_args)
      end
    end

    class RenameInstanceVariableDialog < RenameDialog
      def initialize(plugin)
        super plugin
      end

      def enable_refactor?
        namespace = @script.get_class_on_cursor(@current_buffer.fname, @cursor_line)
        return @script.rename_instance_var?(namespace, @old_value, @txt_new_variable)
      end

      def refactor
        namespace = @script.get_class_on_cursor(@current_buffer.fname, @cursor_line)
        @script.rename_instance_var(namespace, @old_value, @txt_new_variable)
      end
    end

    class RenameClassVariableDialog < RenameDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        namespace = @script.get_class_on_cursor(@current_buffer.fname, @cursor_line)
        return [namespace, @old_value, @txt_new_variable]
      end

      def enable_refactor?
        return @script.rename_class_var?(*setup_args)
      end

      def refactor
        @script.rename_class_var(*setup_args)
      end
    end

    class RenameGlobalVariableDialog < RenameDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        [@old_value, @txt_new_variable]
      end

      def enable_refactor?
        return @script.rename_global_var?(*setup_args)
      end

      def refactor
        @script.rename_global_var(*setup_args)
      end
    end

    class RenameMethodDialog < RenameDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        namespace = @script.get_class_on_cursor(@current_buffer.fname, @cursor_line)
        old_methods = [::RRB::Method.new(namespace, @old_value)]
        return [old_methods, @txt_new_variable]
      end

      def enable_refactor?
        return @script.rename_method?(*setup_args)
      end

      def refactor
        @script.rename_method(*setup_args)
      end
    end

    class RenameConstantDialog < RenameDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        namespace = @script.get_class_on_cursor(@current_buffer.fname, @cursor_line)
        old_const = namespace.name + '::' + @old_value
        return [old_const, @txt_new_variable]
      end

      def enable_refactor?
        return @script.rename_constant?(*setup_args)
      end

      def refactor
        @script.rename_constant(*setup_args)
      end
    end

    class ExtractMethodDialog < RefactorDialog
      def initialize(plugin)
        super plugin
        @txt_new_method = plugin.app.get_user_input
        do_it
      end

      def setup_args
        fail "no selection!" if @app.selection.nil? || @app.selection.invalid?
        start_line = @app.selection.s.y + 1
        end_line   = @app.selection.e.y + 1
        new_method = @txt_new_method
        return [@current_buffer.fname, new_method, start_line, end_line]
      end

      def enable_refactor?
        return @script.extract_method?(*setup_args)
      end

      def refactor
        @script.extract_method(*setup_args)
      end
    end

    class MoveMethodDialog < RefactorDialog
      def initialize(plugin)
        super plugin

        buf = plugin.app.current_buffer
        begin
          plugin.app.switch_to_buffer EditorApp.new_buffer(plugin.app, :no_blank_line)
          methods = @script.refactable_methods.to_a
          methods.each_with_index { 
            |meth,idx| 
            plugin.app.current_buffer.lines << BufferLine.new("#{idx+1}: #{meth.name}")
          }
          num = plugin.app.get_user_input.to_i
          if num == 0
            plugin.app.status_bar_edit_line "invalid number!"
            return
          end
          @cmb_target_method = methods[num-1].name
          classes = @script.refactable_classes.to_a
          classes.each_with_index { 
            |class_name,idx| 
            plugin.app.current_buffer.lines << BufferLine.new("#{idx+1}: #{class_name}")
          }
          num = plugin.app.get_user_input.to_i
          if num == 0
            plugin.app.status_bar_edit_line "invalid number!"
            return
          end
          @cmb_destination = classes[num-1]
        ensure
          plugin.app.switch_to_buffer buf
        end
        do_it
      end
    end
    
    class PushdownMethodDialog < MoveMethodDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        method_name = ::RRB::Method[@cmb_target_method]
        new_namespace = ::RRB::Namespace.new(@cmb_destination)
        return [method_name, new_namespace, @current_buffer.fname, @cursor_line]
      end

      def enable_refactor?
        return @script.pushdown_method?(*setup_args)
      end

      def refactor
        @script.pushdown_method(*setup_args)
      end
    end

    class PullupMethodDialog < MoveMethodDialog
      def initialize(plugin)
        super plugin
      end

      def setup_args
        method_name = ::RRB::Method[@cmb_target_method]
        new_namespace = ::RRB::Namespace.new(@cmb_destination)
        return [method_name, new_namespace, @current_buffer.fname, @cursor_line]
      end

      def enable_refactor?
        return @script.pullup_method?(*setup_args)
      end

      def refactor
        @script.pullup_method(*setup_args)
      end
    end

end
end

rescue LoadError => e
    warn "Ruby Refactoring Browser support disabled"
end
