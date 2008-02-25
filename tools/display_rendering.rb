#!/usr/bin/ruby
$:.unshift(File.dirname((File.readlink($0) rescue $0)) + "/../lib/") unless $win32 
require "curses-ui"
require "yaml"
require "lab"
module Ruvi
   class EditorApp
      def self.perform_layout status_bar = nil, app = nil
      end
   end
end
include Ruvi
def display_filename filename
   screen = WinDescs::instance.stdscr
   int = Marshal.load IO.read(filename)
   0.upto(int.buffer.length - 1) {
      |y|
      x = 0
      screen.setpos y, 0
      int.buffer[y].each_byte {
         |byte|
         break if x >= screen.maxx
         attr = int.attr_buffer[y][x]
         screen.set_attr attr.bold, attr.fg, attr.bg unless attr.nil?
         screen.addstr byte.chr
         x += 1
      }
      screen.refresh
   }
end
begin
   Curses.int_init
   args = ARGV.dup
if args.delete "-c"
   filename = args.shift
   raise "-c expects only one filename. sure you meant to use -c?" \
      unless args.empty?
   loop {
      display_filename filename
      ch = Curses.getch
      exit if ch == ?q
      display_filename "tests/renderings/#{filename}"
      ch = Curses.getch
      exit if ch == ?q
   }
else
   raise "sure you didn't mean -c? one or more of your filenames wasn't in tests/renderings! " \
      if args.detect { |fn| fn !~ %r|^tests/renderings/.*$| }
   args.each {
      |filename|
      display_filename filename
      ch = Curses.getch
      exit if ch == ?q
   }
end
ensure
   Curses.int_finish
end
