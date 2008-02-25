all:
	ruby -wc ruvi
	ruby -wc shikaku.rb
	ruby -wc testcases.rb
	rcov -o ~/arch-co/lyp.xs4all.nl/htdocs/+generated/profiling -p testcases.rb
	rcov -o ~/arch-co/lyp.xs4all.nl/htdocs/+generated/coverage testcases.rb
	lynx -nolist -dump http://localhost:8080/+generated/coverage/ -hiddenlinks=ignore
