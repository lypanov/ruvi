require 'rpa/install'
 
class Install_ruvi < RPA::Install::FullInstaller
    name "ruvi-prerelease"
    version "0.4.12-7"
    classification Application
    build do
       installdocs %w[BUGS README VersionLog]
       installdocs "docs"
       installtests "tests"
       skip_default Installrdoc
    end
    install { skip_default RunUnitTests }
    description <<EOF
Vim Wannabe.
 
Ruvi includes a large subset of vim functionality; it features syntax
highlighting for Ruby and C++ (partial) and auto-indentation. NOTE: ruvi won't 
work with the win32 Rubyinstaller since it doesn't include curses.
EOF
end
