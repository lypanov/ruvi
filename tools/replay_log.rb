#!/usr/bin/ruby
$:.unshift(File.dirname((File.readlink($0) rescue $0)) + "/../lib/") unless $win32 
require "curses-ui"
require "yaml"
require "lab"
args = ARGV.dup
raise "sorry, bad command line usage" if args.size != 1
filename = args.shift
$replaying = true
require "buffer.rb"
require "optparse"
$action_replay_log = Marshal.load(IO.read filename)
require "shikaku.rb"
