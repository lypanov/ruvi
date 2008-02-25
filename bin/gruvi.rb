# Distributed under the same terms as Ruby/GTK2. For details,
# please see http://ruby-gnome2.sourceforge.jp/

$win32 = true

prefix_dir = begin
t = File.readlink($0) rescue $0
File.dirname(t)
rescue NotImplementedError => e
File.dirname($0)
end
$:.unshift "#{prefix_dir}/../lib"

require 'lab'
require 'singleton'
require 'gtk2'

include Gtk

class Hash
    def dup_with_override overrides
       tmp = self.dup
       overrides.each_pair {
            |key,val|
            tmp[key] = val
       }
       tmp
    end
end

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

PretendConfigureEvent = Struct.new :width, :height

module Ruvi
module Curses

    def Curses.keyname ch
        p "key : '#{Gdk::Keyval.to_name(ch)}'"
        raise
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
    def Curses.int_init
        # prealloc using a stupid default, 
        #   - we get a resize request once we are mapped in any case
        Curses.layout PretendConfigureEvent.new(10,10)
        
        Gtk::init

        controller = Gtk::MDI::Controller.new(Ruvi::MyEditor, :notebook)
        controller.signal_connect('window_removed') do 
          |controller, window, last|
          Gtk::main_quit if last
        end

        window = controller.open_window
        window.notebook.set_tab_pos(Gtk::POS_TOP)
        window.populate

        $daed = window
    end
    def Curses.close_screen
        exit
    end
    def Curses.int_finish
    end
    def Curses.end_it_all
        close_screen
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
    KEY_UP = Gdk::Keyval::GDK_Up
    KEY_DOWN = Gdk::Keyval::GDK_Down
    KEY_LEFT = Gdk::Keyval::GDK_Left
    KEY_RIGHT = Gdk::Keyval::GDK_Right
    KEY_NPAGE = 0
    KEY_PPAGE = 0
end

class EditorApp
    def input_loop
        puts "START"
        $daed.exec
        puts "DONE"
    end
end
end

module Gtk
  module MDI
    # A simple notebook "label" (HBox container) with a text
    # label and a close button.
    class NotebookLabel < HBox
      type_register

      def initialize(str='')
        super()
        self.homogeneous = false
        self.spacing = 4
        
        @label = Label.new(str)
        
        @button = Button.new
        @button.set_border_width(0)
        @button.set_size_request(16, 16)
        @button.set_relief(RELIEF_NONE)

        image = Image.new
        image.set(:'gtk-close', IconSize::MENU)
        @button.add(image)
        
        pack_start(@label, true, false, 0)
        pack_start(@tv, false, false, 0)
        pack_start(@button, false, false, 0)

        show_all
      end
      
      attr_reader :label, :button

      def text
        @label.text
      end

      def text=(str)
        @label.text = str
      end
    end


    # An MDI document container class.
    class Document < GLib::Object
      type_register
      signal_new('close',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'])

      def initialize(widget, title='Untitled')
        super()
        @title = title
        @widget = widget
        @label = NotebookLabel.new(title)
        @label.button.signal_connect('clicked') do |widget, event|
          signal_emit('close')
        end
      end
      
      attr_reader :widget, :label

      def title
        @label.text
      end

      def title=(str)
        @label.text = str
      end

    private
      def signal_do_close ; end
    end

    DragInfo = Struct.new('DragInfo', :in_progress, :x_start, :y_start,
                          :document, :motion_handler)

    # An MDI notebook widget that uses MDI::Document objects and supports
    # drag-and-drop positioning.
    class Notebook < Gtk::Notebook
      type_register
      signal_new('document_added',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkMDIDocument'])  # the document that was added
      signal_new('document_removed',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkMDIDocument'],  # the document that was removed
                 GLib::Type['gboolean'])        # @documents.empty?
      signal_new('document_close',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkMDIDocument'])  # the document requesting close
      signal_new('document_drag',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkMDIDocument'],  # the document being dragged
                 GLib::Type['gint'],            # the pointer's x-coordinate
                 GLib::Type['gint'])            # the pointer's y-coordinate
      signal_new('document_dropped',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkMDIDocument'],  # the document that was dropped
                 GLib::Type['gint'],            # the drop x-coordinate
                 GLib::Type['gint'])            # the drop y-coordinate

      def initialize
        super
        @documents = []
        @handlers = {}
        @drag_info = DragInfo.new(false)

        add_events(Gdk::Event::BUTTON1_MOTION_MASK)
        signal_connect('button-press-event') do |widget, event|
          button_press_cb(event)
        end
        signal_connect('button-release-event') do |widget, event|
          button_release_cb(event)
        end

        self.scrollable = true
      end

      attr_reader :drag_info

      def add_document(doc)
        return if doc.nil?
        append_page(doc.widget, doc.label)

        h = []
        h << doc.signal_connect('close') do
          signal_emit('document_close', doc)
        end
        @handlers[doc] = h

        @documents << doc
        signal_emit('document_added', doc)
      end

      def remove_document(doc)
        return unless @documents.include? doc

        @handlers[doc].each do |handler|
          doc.signal_handler_disconnect(handler)
        end
        @handlers.delete(doc)

        @documents.delete(doc)
        remove_page(index_of_document(doc))
        signal_emit('document_removed', doc, @documents.empty?)
      end

      def focus_document(doc)
        return unless @documents.include? doc
        index = index_of_document(doc)
        self.page = index
      end

      def shift_document(document, new_index)
        index = index_of_document(document)
        return if index == new_index or index.nil? or new_index.nil?
        reorder_child(document.widget, new_index)
        self.page = new_index
      end

      # QTP: Should this really emit 'document_removed' and
      # 'document_added'?  It's certainly convenient (for me)...
      def migrate_document(document, dest)
        index = index_of_document(document)
        return if index.nil? or not dest.is_a? Notebook

        drag_stop
        Gtk::grab_remove(self)
        remove_document(document)

        dest.instance_eval do
          add_document(document)
          drag_start
          @drag_info.document = document
          @drag_info.motion_handler = signal_connect('motion-notify-event') do
            |widget, event|
            motion_notify_cb(event)
          end
        end
      end

      def documents
        @documents.dup
      end

      def index_of_document(document)
        children.index(document.widget)
      end

      def document_at_index(index)
        page = children[index]
        @documents.each do |document|
          return document if document.widget == page
        end
        return nil
      end

      def spans_xy?(x, y)
        win_x, win_y = toplevel.window.origin
        rel_x, rel_y = x - win_x, y - win_y

        nb_x, nb_y = allocation.x, allocation.y
        width, height = allocation.width, allocation.height

        rel_x >= nb_x and rel_y >= nb_y and 
          rel_x <= nb_x + width and rel_y <= nb_y + height
      end

      def document_at_xy(x, y)
        document_at_index(index_at_xy(x, y))
      end

      def index_at_xy(x, y)
        nb_x, nb_y = window.origin
        x_rel, y_rel = x - nb_x, y - nb_y

        nb_bx, nb_by = nb_x + allocation.width, nb_y + allocation.height
        return nil if x < nb_x or x > nb_bx or y < nb_y or y > nb_by

        index = nil
        first_visible = true

        children.each_with_index do |page, i|
          label = get_tab_label(page)
          next unless label.mapped?

          la_x, la_y  = label.allocation.x, label.allocation.y

          if first_visible
            first_visible = false
            x_rel = la_x if x_rel < la_x
            y_rel = la_y if y_rel < la_y
          end

          if self.tab_pos == Gtk::POS_TOP or
              self.tab_pos == Gtk::POS_BOTTOM
            break unless la_x <= x_rel
            if la_x + label.allocation.width <= x_rel
              index = i + 1
            else
              index = i
            end
          else
            break unless la_y <= y_rel
            if la_y + label.allocation.height <= y_rel
              index = i + 1
            else
              index = i
            end
          end
        end

        return -1 if index == children.length
        return index
      end

    private
      def signal_do_document_added(doc) ; end
      def signal_do_document_removed(doc, last) ; end
      def signal_do_document_close(doc) ; end
      def signal_do_document_drag(doc, x, y) ; end
      def signal_do_document_dropped(doc, x, y) ; end

      def button_press_cb(event)
        return true if @drag_info.in_progress
        
        index = index_at_xy(event.x_root, event.y_root)
        return false if index.nil?
        document = document_at_index(index)

        if event.button == 1 and 
            event.event_type == Gdk::Event::BUTTON_PRESS and
            index >= 0
          @drag_info.document = document
          @drag_info.x_start, @drag_info.y_start = event.x_root, event.y_root
          @drag_info.motion_handler = signal_connect('motion-notify-event') do
            |widget, event|
            motion_notify_cb(event)
          end
        end

        return false
      end

      def button_release_cb(event)
        if @drag_info.in_progress
          signal_emit('document_dropped',
                      @drag_info.document, event.x_root, event.y_root)
          if Gdk::pointer_is_grabbed?
            Gdk::pointer_ungrab(Gdk::Event::CURRENT_TIME)
            Gtk::grab_remove(self)
          end
        end
        
        drag_stop
        return false
      end

      def motion_notify_cb(event)
        unless @drag_info.in_progress
          return false unless Gtk::Drag::threshold?(self, @drag_info.x_start, 
                                                    @drag_info.y_start,
                                                    event.x_root, event.y_root)
          drag_start
        end
        signal_emit('document_drag',
                    @drag_info.document, event.x_root, event.y_root)
      end

      def drag_start
        @drag_info.in_progress = true
        Gtk::grab_add(self)
        unless Gdk::pointer_is_grabbed?
          Gdk::pointer_grab(self.window, false,
                            Gdk::Event::BUTTON1_MOTION_MASK |
                            Gdk::Event::BUTTON_RELEASE_MASK, nil,
                            Gdk::Cursor.new(Gdk::Cursor::FLEUR),
                            Gdk::Event::CURRENT_TIME)
        end
      end

      def drag_stop
        signal_handler_disconnect(@drag_info.motion_handler) unless 
          @drag_info.motion_handler.nil?
        @drag_info = DragInfo.new(false)
      end
    end

    # A controller for managing MDI windows.
    class Controller < GLib::Object
      type_register
      signal_new('window_added',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkWindow'])       # the window that was added
      signal_new('window_removed',
                 GLib::Signal::RUN_FIRST,
                 nil,
                 GLib::Type['void'],
                 GLib::Type['GtkWindow'],       # the window that was removed
                 GLib::Type['gboolean'])        # @windows.empty?

      def initialize(window_class, notebook_attr, *args)
        super()
        @windows = []
        @handlers = {}
        @window_class = window_class
        @notebook_attr = notebook_attr
        @args = args
      end
      
      def open_window(*args)
        window = @window_class.new(*args)
        window.show_all
        add_window(window)
      end

      def add_window(window)
        @windows << window
        window.signal_connect('destroy') {remove_window(window)}
        n = nb(window)

        h = []
        h << n.signal_connect('document_close') do |nb, doc|
          nb.remove_document(doc)
        end
        h << n.signal_connect('document_removed') do |nb, doc, last|
          close_window(window) if last
        end
        h << n.signal_connect('document_drag') do |nb, doc, x, y|
          document_drag_cb(window, nb, doc, x, y)
        end
        h << n.signal_connect('document_dropped') do |nb, doc, x, y|
          document_dropped_cb(window, nb, doc, x, y)
        end
        @handlers[window] = h

        signal_emit('window_added', window)
        return window
      end

      def close_window(window)
        return unless @windows.include? window
        window.destroy
        remove_window(window)
      end

      def remove_window(window)
        return unless @windows.include? window

        n = nb(window)
        @handlers[window].each do |handler|
          n.signal_handler_disconnect(handler)
        end
        @handlers.delete(window)

        @windows.delete(window)
        signal_emit('window_removed', window, @windows.empty?)
        return window
      end

      def windows
        @windows.dup
      end

      def documents
        documents = []
        @windows.each do |window|
          notebook = nb(window)
          documents += notebook.documents
        end
        return documents
      end

    private
      def signal_do_window_added(window) ; end
      def signal_do_window_removed(window, last) ; end

      def nb(window)
        window.method(@notebook_attr).call
      end

      def document_drag_cb(window, notebook, document, x, y)
        dest = notebook_at_pointer
        return if dest.nil?

        index = dest.index_at_xy(x, y)
        notebook.migrate_document(document, dest) if dest != notebook
        dest.shift_document(document, index)
      end

      def document_dropped_cb(window, notebook, document, x, y)
        dest = notebook_at_pointer
        if dest.nil? and not notebook.children.length == 1
          window = open_window(*@args)
          width, height = window.size
          window.move(x - width / 2, y - height / 2)
          dest = nb(window)
          notebook.migrate_document(document, dest)
          dest.instance_eval do
            drag_stop
            Gtk::grab_remove(self)
          end
        else
          # so we moved the document to an existing notebook... 
          # should a signal be emitted?  who cares?
        end
      end

      def window_and_xy_at_pointer
        window, x_rel, y_rel = Gdk::Window::at_pointer
        unless window.nil? or window.toplevel.nil? or 
            window.toplevel.user_data.nil?
          win = window.toplevel.user_data
          x, y = window.origin
          return win, x + x_rel, y + y_rel if @windows.include? win
        end
        return nil, 0, 0
      end

      def notebook_at_pointer
        window, x, y = window_and_xy_at_pointer
        return nil if window.nil?
        notebook = nb(window)
        return nil unless notebook.spans_xy?(x, y)
        return nb(window)
      end

    end
  end
end


module Ruvi

class TextWidgetThingy
include LabThingy

def initialize editor
    @tag_table_okay = false
    @editor = editor
    init_lab_thingy editor
    @last_cursor_y = nil
end
   def maxx
      WinDescs::instance.stdscr.maxx
   end
   def maxy
      WinDescs::instance.stdscr.maxy
   end

def iterate_over_tag_text_pairs line_num
    line = @editor.buffer[line_num]
    x = 0
    iterate_over_attr_runs(line_num) {
        |len, attr|
        yield attr, line[x, len]
        x += len
    }
end

def iterate_over_attr_runs line_num
    attrs = @editor.attr_buffer[line_num]
    attr_run = []
    run_attr = nil
    run_len = 0
    attrs.each {
        |attr|
        if attr.nil?
            run_len += 1
        else
            if !run_attr.nil?
                yield run_len, run_attr
            end
            run_attr, run_len = attr, 1
        end
    }
    yield run_len, run_attr
end

attr_reader :textview
attr_accessor :was_resized

  def iter_for_xy x, y
    buffer = @editor.textview.buffer
    iter = buffer.start_iter
    iter.line, iter.line_index = y, x
    iter
  end

  def visualize_current_position buffer
    # first we remove the tags from the current line
    if !@last_y.nil?
        first_char = iter_for_xy 0, @last_y
        last_char = iter_for_xy 0, @last_y
        last_char.forward_to_line_end
        buffer.remove_tag buffer.tag_table.lookup("current_line"), first_char, last_char
        buffer.remove_tag buffer.tag_table.lookup("current_character"), first_char, last_char
    end
    # we are always one char away from the end of line delimiter therefore its always safe to use forward_char
    curr_char = iter_for_xy @x, @y
    next_char = iter_for_xy @x, @y
    next_char.forward_char
    buffer.apply_tag buffer.tag_table.lookup("current_character"), curr_char, next_char
    # lets highlight the current line
    first_char = iter_for_xy 0, @y
    last_char = iter_for_xy 0, @y
    last_char.forward_to_line_end
    buffer.apply_tag buffer.tag_table.lookup("current_line"), first_char, last_char
    # now we place the cursor
    cursor = iter_for_xy @x, @y
    buffer.place_cursor cursor
    @last_y = @y
  end

  def render_line buffer, y
    first_char = iter_for_xy 0, @y
    last_char = iter_for_xy 0, @y
    last_char.forward_to_line_end
    last_char.backward_char
    # buffer.delete first_char, last_char
    iter = buffer.start_iter
    iter.line = y
    iterate_over_tag_text_pairs(y) {
        |attr, str|
        fg, bg = attr.fg, attr.bg
        fg = :black if fg == 0
        bg = :white if bg == 0
        buffer.insert iter, str, @background_tags[bg], @foreground_tags[fg]
    }
  end

  def init_text
    buffer = @editor.textview.buffer
    init_tag_table buffer
    # we see an infinite resize loop if we set buffer.text to something bigger than the canvas!
    allocated_lines = buffer.text.count "\n"
    # puts "we have #{allocated_lines} need #{@editor.last_resize_ev.height}"
    if allocated_lines < (@editor.last_resize_ev.height - 1)
        buffer.text = "\n" * @editor.last_resize_ev.height
    end
    rendered_ys = []
    @invalids.each {
        |invalid|
        next if rendered_ys.include?  invalid.y
        rendered_ys << invalid.y
        # puts "got an invalidation of #{invalid.y}"
        render_line buffer, invalid.y
    }
    @invalids.clear
    visualize_current_position buffer
  end

  def init_tag_table buffer
    return if @tag_table_okay
    default = { "family" => "monospace", "size_points" => 8 }
    @background_tags, @foreground_tags = {}, {}
    [:black].collect {
        |sym|
        @background_tags[sym] = buffer.create_tag("bg_#{sym.to_s}", default.dup_with_override({ "background" => sym.to_s }))
    }
    [:black, :white, :yellow, :red, :cyan, :blue, :magenta, :green].collect {
        |sym|
        @foreground_tags[sym] = buffer.create_tag("fg_#{sym.to_s}", default.dup_with_override({ "foreground" => sym.to_s }))
    }
    buffer.create_tag "current_line",      default.dup_with_override({ "background" => "#444444" })
    buffer.create_tag "current_character", default.dup_with_override({ "background" => "white", "foreground" => "black" })
    [:white, :yellow, :red, :cyan, :blue, :magenta, :green].collect {
        |sym|
        @background_tags[sym] = buffer.create_tag("bg_#{sym.to_s}", default.dup_with_override({ "background" => sym.to_s }))
    }
    buffer.tag_table.each {
        |tag| 
        puts "tag.name -> #{tag.name} : #{tag.priority}"
    }
    @tag_table_okay = true
  end
end


class MyEditor < Gtk::Window
   include Lab

   @started = false
   @@started = false

   attr_reader :textview, :twt, :app

   def exec
      @@started = true
      # block
      Gtk::main
   end

   def refresh
      return if @@started
      @twt.update
   end

  @@count = 0

  def initialize
    super
    @was_resized = false
    @@myeditor = self
    @twt = TextWidgetThingy.new self
    init_buffer_abstraction
    @notebook = Gtk::MDI::Notebook.new
    add(@notebook)
    set_title("#{self.class} #{@@count}")
    set_size_request(320, 240)
  end

  attr_reader :last_resize_ev

  def populate
    @app = EditorApp.app_instance
    @textview = TextView.new
    @textview.set_editable false
    @textview.signal_connect('key_release_event') {
        |widget, event, user_data|
        ch = event.keyval
        case ch
        when Gdk::Keyval::GDK_Return
            ch = ?\r
        when Gdk::Keyval::GDK_Escape
            ch = ?\e
        when Gdk::Keyval::GDK_BackSpace
            ch = ?\b
        when Gdk::Keyval::GDK_Alt_L, Gdk::Keyval::GDK_Tab
            next
        end
        # p event.hardware_keycode
        @app.send_key ch unless ch == false
        @app.flush_finish_redraw @app.current_buffer
        @twt.init_text
    }
    @textview.signal_connect('size_allocate') {
        |window, allocation|
        resize_ev = PretendConfigureEvent.new allocation.width / 7, allocation.height / 14
        Curses.layout resize_ev 
        if resize_ev != @last_resize_ev
            puts "doing redraw"
            @app.redraw @app.current_buffer
        end
        @last_resize_ev = resize_ev 
        @app.flush_finish_redraw @app.current_buffer
        @twt.init_text
    }
    @notebook.add_document(Gtk::MDI::Document.new(@textview, "label?"))
    @notebook.show_all
    @textview.can_focus = true
    @textview.grab_focus
    @@started = false
  end

  attr_reader :sx, :sy, :notebook
end

end

require "shikaku.rb"
require "lab.rb"
