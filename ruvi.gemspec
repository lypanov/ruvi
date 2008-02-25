require 'rubygems'

spec = Gem::Specification.new do |s|
    s.name = "ruvi-prerelease"
    s.version = "0.4.12"
    s.summary = <<-EOF
      Pure Ruby Vim-wannabe
    EOF
    s.description = <<-EOF
      Ruvi includes a large subset of Vim/Vi functionality.
      Due to the fact that its written in pure Ruby it is
      trivial to extend and to implement missing vi functionality
      as plugins. It includes a gtk2 frontend and curses frontend.
    EOF

    s.files = <<EOF.split "\n"
bin/ruvi.bat
bin/ruvi
bin/kkaku.rb
bin/gruvi.rb
lib/3rdparty/aelexer/string.rb
lib/3rdparty/aelexer/lexer.rb
lib/3rdparty/breakpoint.rb
lib/3rdparty/binding_of_caller.rb
lib/plugins/rrb_plugin.rb
lib/plugins/hl_cpp.rb
lib/plugins/hl_ae.rb
lib/plugins/completion.rb
lib/plugins/hl_plain.rb
lib/widgets.rb
lib/timemachine.rb
lib/shikaku.rb
lib/search.rb
lib/movement.rb
lib/lab.rb
lib/highlighters.rb
lib/front.rb
lib/debug.rb
lib/curses-ui.rb
lib/commands.rb
lib/bindings.rb
lib/selections.rb
lib/buffer.rb
lib/misc.rb
lib/virtualbuffers.rb
lib/baselibmods.rb
README
BUGS
EOF

    s.bindir = "bin"
    s.require_path = 'lib'
    s.executables = ["ruvi"]
    s.default_executable = "ruvi"

    s.has_rdoc = false
    s.test_suite_file = "tests/tc_all.rb"

    s.author = "Alexander Kellett"
    s.email = "ruvi-gem@lypanov.net"
    s.homepage = "http://www.lypanov.net/xml/development/ruvi.xml"
    s.rubyforge_project = "ruvi"
end
