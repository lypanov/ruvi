@echo off
if "%OS%" == "Windows_NT" goto WinNT
ruby -Sx "%0" %1 %2 %3 %4 %5 %6 %7 %8 %9
goto endofruby
:WinNT
ruby -Sx "%~nx0" %*
goto endofruby
#!/bin/ruby
$win32=1
Kernel.load "ruvi"
__END__
:endofruby
