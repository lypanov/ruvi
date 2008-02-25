class LexerBase
	def initialize
		@states = []
		@result = []
		@result_endofline = nil
	end
	attr_reader :states, :result, :result_endofline

	def set_states(states)
		@states = states
	end
	def set_result(result)
		@result = result
	end
	def format(text, state_output)
		@result << [text, state_output]
	end
	def format2(text, state_output)
		if @result.empty? != true and @result.last[1] == state_output
			@result.last[0] << text
		else
			@result << [text, state_output]
		end
	end
	def format_end(state_output)
		@result_endofline = state_output
	end
	def match(regexp, output)
		m = regexp.match(@text)
		return false unless m
		txt = @text.slice!(0, m.end(0))
		format(txt, output)
		true
	end
	def lex_line(text)
		raise "derived class #{self.class} must overload #lex_line."
	end
	def self.profile
		lines = IO.readlines(__FILE__)
		lexer = self.new
		$logger.debug(1) { "profiling the #{self.inspect} lexer (this may take some time)" }
		require 'profiler'
		Profiler__.start_profile
		lines.each do |line|
			lexer.set_states([])
			lexer.set_result([])
			lexer.lex_line(line)
		end
		Profiler__.print_profile(STDOUT)
	end
	def self.benchmark
		n = 10000
		$logger.debug(1) { "benchmarking the lexers (computing #{n} lines " + 
			"with GC disabled)" }
		require 'benchmark'
		Benchmark.bm(20) do |b|
			lexer = LexerRuby::Lexer.new
			lines = IO.readlines(__FILE__)
			GC.disable
			b.report("#{lexer.class}") do
				n.times do |i|
					lexer.set_states([])
					lexer.set_result([])
					lexer.lex_line(lines[i%lines.size].clone)
				end
			end
			GC.enable
		end
	end
end

module LexerText

class Lexer < LexerBase
	RE_TAB = /\A\t+/  
	RE_NOTTAB = /\A[^\t]+/  
	def lex_line(text)
		@text = text
		until @text.empty?
			if match(RE_TAB, :tab)
			else
				match(RE_NOTTAB, :text)
			end
		end
	end
end # class Lexer

end # module LexerText


module LexerCplusplus

module State

class Base
end

class Comment < Base
	def ==(other)
		(self.class == other.class)
	end
end

class Preprocessor < Base
	def ==(other)
		(self.class == other.class)
	end
end

class Assembler < Base
	def ==(other)
		(self.class == other.class)
	end
end

end # module State

class LexerCplusplus < LexerBase
	BAD_TOKENS = [
		'"[^"]*$',                    # "bad string     string
		'\'\'',                       # ''              char empty
	  '\'(?:[^\'\\\\]|\\\\.){2,}?\'', # 'ab' 'x\n'    char overfilled
		'\'[^\']*(?=/\*)',            # 'ab /*          char until comment
		'\'[^\']*$',                  # 'ab \n          char until newline
		'[1-9]\d*[[:alpha:]_][[:alnum:]_]*' # 3a7z      number/ident
	]
	GOOD_TOKENS = [
		'\s*#\s*[[:alpha:]].*$',      # #define max \   preprocessor
		'"(?:[^\\\\]|\\\\.)*?"',      # "ab"    "\n\r"  string
		'\'(?:[^\\\\]|\\\\.)\'',      # 'a'     '\n'    char
		'/(?:\*|\*.*\*)/',            # /*/     /*x*/   mcomment (oneline)
		'/[/\*].*$',                  # // a    /* b    comment/mcomment
		'_{0,2}asm\\s*\\{.*$',        # asm{            assembler
		'[[:alpha:]_][[:alnum:]_]*',  # _value  pix2_3  identifier
		'0[xX][[:xdigit:]]+',         # 0xabc   0xbabe  number as hex 
		'\d+\.\d+',                   # 0.123   32.10   number as float
		'\d+',                        # 42      999     number as integer
		'.'                           #                 catch all
	]
	RE_TOKENIZE = Regexp.new(
		'(' + BAD_TOKENS.join('|') + ')|' +
		'(' + GOOD_TOKENS.join('|') + ')'
	)

	def tokenize(string)
		string.scan(RE_TOKENIZE)
	end
	keywords = %w(auto break bool case catch char class) +
		%w(const_cast const continue default delete) +
		%w(double do dynamic_cast else enum) +
		%w(extern false float for friend) +
		%w(goto if inline int long mutable) +
		%w(namespace new operator private protected public) +
		%w(reinterpret_cast return short signed sizeof) +
		%w(static_cast static struct switch template this) +
		%w(throw true try typedef typename typeid) +
		%w(union using unsigned virtual void volatile)
	RE_KEYWORD = Regexp.new(
		'\A(?:' + keywords.join('|') + ')\z'
	)
	def format_with_tabs(text, symnormal, symtab)
		text.scan(/(\t+)|([^\t]+)/) do |s1, s0|
			format(s1, symtab) if s1
			format(s0, symnormal) if s0
		end
	end
	def lex_line_normal(text)
		tokens = tokenize(text)
		# check for preprocessor here
		if tokens.size == 1
			bad, good = tokens[0]
			m = /(\A\s*)(#.*\\$)/.match(good)
			if m
				@states << State::Preprocessor.new
				spaces = m[1]
				format(spaces, :space) unless spaces.empty?
				format_with_tabs(m[2], :preproc, :preproc_tab)
				format_end(:preproc_end)
				return
			end
			m = /(\A\s*)(#.*$)/.match(good)
			if m
				spaces = m[1]
				format(spaces, :space) unless spaces.empty?
				format_with_tabs(m[2], :preproc, :preproc_tab)
				return
			end
		end
		# check for normal code
		tokens.each do |bad, good|
			$logger.debug(2) { "processing bad=#{bad}  good=#{good}" }
			if bad
				format(bad, :bad) 
				next 
			end
			state = case good
			when /\A(?:"|')./
				good.scan(/((?:\\.|[\t])+)|([^\\\t]+)/) do |s1, s0|
					format(s1, :string1) if s1
					format(s0, :string) if s0
				end
				nil
			when /\A_{0,2}asm\s*\{.*$/
				@states << State::Assembler.new
				format_with_tabs(good, :assembler, :assembler_tab)
				format_end(:assembler_end)
				nil
			when RE_KEYWORD
				:keyword
			when /\A\/ (?: \* | \* .* \* ) \/\z/x
				format_with_tabs(good, :mcomment, :mcomment_tab)
				nil
			when /\A\/\*/
				@states << State::Comment.new
				format_end(:mcomment_end)
				format_with_tabs(good, :mcomment, :mcomment_tab)
				nil
			when /\A\/\//
				format_end(:comment_end)
				format_with_tabs(good, :comment, :comment_tab)
				nil
			when /\A[[:alpha:]_]/
				:ident
			when /\A[[:punct:]]/
				:punct
			when /\A[[:digit:]]/
				:number
			when /\A\t+/
				:tab
			when /\A\s+/
				:space
			else
				:any
			end
			format(good, state) if state
		end
	end
	def lex_line_comment(text)
		m = /\A.*?\*\//.match(text)
		if m
			@states.shift
			format_with_tabs(m.to_s, :mcomment, :mcomment_tab)
			text.slice!(0, m.end(0))
			return lex_line_normal(text)  # comment */ code
		end
		# we didn't meet end of comment.. so propagate
		format_end(:mcomment_end)
		format_with_tabs(text, :mcomment, :mcomment_tab)
	end
	def lex_line_preproc(text)
		case text
		when /\\$/
			format_with_tabs(text, :preproc, :preproc_tab)
			format_end(:preproc_end)
		else
			# if no tailing backslash
			@states.shift
			format_with_tabs(text, :preproc, :preproc_tab)
		end
	end
	def lex_line_assembler(text)
		m = /\A.*?\}/.match(text)
		if m
			@states.shift
			format_with_tabs(m.to_s, :assembler, :assembler_tab)
			text.slice!(0, m.end(0))
			return lex_line_normal(text)  # asm } code
		else
			# if no close-brace
			format_end(:assembler_end)
			format_with_tabs(text, :assembler, :assembler_tab)
		end
	end
	def lex_line(text)
		if @states.empty? 
			return lex_line_normal(text) 
		end
		state = @states[0]
		case state
		when State::Comment: lex_line_comment(text)
		when State::Preprocessor: lex_line_preproc(text)
		when State::Assembler: lex_line_assembler(text)
		else
			raise "unknown state #{state.class}"
		end
	end
end # class LexerCplusplus

Lexer = LexerCplusplus

end # module LexerCplusplus

require '3rdparty/aelexer/string'

module LexerRuby

module State

class Base
end

class Heredoc < Base
	def initialize(begin_tag, ignore_leading_spaces, interpolate=true)
		@begin_tag = begin_tag
		@ignore_leading_spaces = ignore_leading_spaces
		@interpolate = interpolate
	end
	attr_reader :begin_tag, :ignore_leading_spaces, :interpolate
	def ==(other)
		(self.class == other.class) and
		(@begin_tag == other.begin_tag) and 
		(@ignore_leading_spaces == other.ignore_leading_spaces) and
		(@interpolate == other.interpolate)
	end
end

class Comment < Base
	def ==(other)
		(self.class == other.class)
	end
end

class Endoffile < Base
	def ==(other)
		(self.class == other.class)
	end
end

class Literal < Base
	def initialize(literal_type, symbol, balance)
		super()
		@literal_type = literal_type
		@symbol = symbol
		@balance = balance
	end
	attr_reader :literal_type, :symbol, :balance
	def ==(other)
		(self.class == other.class) and
		(@literal_type == other.literal_type) and
		(@symbol == other.symbol) and
		(@balance == other.balance)
	end
end

class String < Base
	def initialize(symbol)
		super()
		@symbol = symbol
	end
	attr_reader :symbol
	def ==(other)
		(self.class == other.class) and
		(@symbol == other.symbol)
	end
end

end # module State

class Lexer < LexerBase
	GVAR = Regexp.escape(%q(~*$!@/\\;,.=:<>"-&`'+))
	PUNCT = ['(', ')'] + 
		%w(=== ==  =~  =>  =   !=  !~  !) +
		%w(<<  <=> <=  <   >=  >) +
		%w({   }   [   ]) +
		%w(::  :   ... ..) +
		%w(+=  +   -=  -   **  *   /   %) +
		%w(||  |   &&  &) +
		%w(,   ;) 
	ALT_PUNCT = '(?:' + 
		PUNCT.map{|txt|Regexp.escape(txt)}.join('|') + ')'
	
	BAD_TOKENS = [
		'\$(?=\s)',                   # $               gvar
		'\$['+GVAR+']\w+',            # $~x     $.dup   gvar (letter)
		':\d\w*',                     # :2bad           symbol
		'\?\w{2,}',                   # ?bad            number
		'\.{4,}',                     # ....            range
		'@{3,}\w*',                   # @@@x            ivar,cvar
		':{3,}',                      # :::             module A::B
		'[1-9][[:alpha:]]'  # TODO: remove me.. 
	]
	GOOD_TOKENS = [
		'/.*',                        # /abc            multi-regexp
		'%[wWqQrsx]?..*',             # %w(    %|       literal
		'\'(?:[^\\\\]|\\\\.)*?\'',    # '\'x\\' ''      string single quoted
		'"(?:[^\\\\]|\\\\.)*?"',      # "ab"    ""      string double quoted
		'`(?:[^\\\\]|\\\\.)*?`',      # `ls`   `echo`   string backtick
		'["\'`].*',                   # 'ab "xy `12     multi-strings
		':[[:alpha:]_]\w*',           # :sym   :r2d2    symbol
		'<<-?[\'"]?\w+[\'"]?',        # <<A    <<-'B'   heredoc
		'\.\w+[\?\!]?',               # .zap!  .exists? method-name
		'#.*',                        # code # comment  line-comment
		'=begin.*',                   # =begin          multi-comment
		'__END__.*',
		'\?.',                        # ?a     ??       number ascii
		'\$['+GVAR+']',               # $~     $.       gvar (letter)
		'\$\w+',                      # $0     $dbg     gvar (name)
		'@{0,2}[[:alpha:]_]\w*[\?\!]?', # _3val?  @@x_3 identifier
		'0x[[:xdigit:]_]+',           # 0xdeadbeef      number hex
		'0b[_01]+',                   # 0b1100101       number binary
		'\d[\d_]*\.[\d_]+',           # 3.3_3           number float
		'\d[\d_]*',                   # 42              number integer
		ALT_PUNCT,                    # :: ..           puncturation
		'.'                           #                 catch all
	]
	RE_TOKENIZE = Regexp.new(
		'(' + BAD_TOKENS.join('|') + ')|' +
		'(' + GOOD_TOKENS.join('|') + ')'
	)
	#p RE_TOKENIZE.source
	def tokenize(string)
		string.scan(RE_TOKENIZE)
	end
	KEYWORDS = %w(alias and begin BEGIN break case class defined?) +
		%w(def do else elsif end END ensure false for if include) +
		%w(loop module next nil not or raise redo require rescue) +
		%w(retry return self super then true undef unless until) +
		%w(yield when while)
	RE_KEYWORD = Regexp.new(
		'\A(?:' +
		KEYWORDS.map{|txt|Regexp.escape(txt)}.join('|') + 
		')\z'
	)
	RE_REGEXP_OPTIONS = /\A[eimnosux]*\z/
	PAIRS = [['(', ')'], ['{', '}'], ['[', ']'], ['<', '>']]
	def format_string(text, end_char,
		code_normal, code_normal1, code_tab)
		re = case end_char
		when '\''
			/(\t+)|([\\][\\'])|(.)/
		else
			/(\t+)|([\\].|#\{(?:[^\\\\]|[\\\\].)*?\})|(.)/
		end
		text.scan(re) do |s2, s1, s0|
			format(s2, code_tab) if s2
			format(s1, code_normal1) if s1
			format2(s0, code_normal) if s0
		end
	end
	def format_heredoc(text, interpolate)
		re = if interpolate
			/(\t+)|([\\].|#\{(?:[^\\\\]|[\\\\].)*?\})|(.)/
		else
			/(\t+)|(\t+)|(.)/
		end
		text.scan(re) do |s2, s1, s0|
			format(s2, :heredoc_tab) if s2
			format(s1, :heredoc1) if s1
			format2(s0, :heredoc) if s0
		end
	end
	def format_literal(text, interpolate, *chars)
    ending = !@states.first.is_a?(LexerRuby::State::Literal)
		re = if interpolate
			/(\t+)|([\\].|#\{(?:[^\\\\]|[\\\\].)*?\})|(.)/
		else
			/(\t+)|([\\].)|(.)/
		end
    to_print = nil
    if ending
      to_print = text[-1, 1]
      text = text[0..-2]
    end
		text.scan(re) do |s2, s1, s0|
			format(s2, :literal_tab) if s2
			if s1 and chars.size > 0
				escaped_letter = s1[1, 1]
				ok = chars.any?{|char| escaped_letter.include?(char)}
				$logger.debug(2) { "filter s1=#{s1.inspect} chars=#{chars.inspect} ok=#{ok.inspect}" }
				s0, s1 = s1, nil unless ok
			end
			format(s1, :literal1) if s1
			format2(s0, :literal) if s0
		end
    format(to_print, :literal_ending) if ending
	end
	def format_comment(text, code_normal, code_tab)
		re = /(\t+)|(.)/
		text.scan(re) do |s1, s0|
			format(s1, code_tab) if s1
			format2(s0, code_normal) if s0
		end
	end
	def token_literal(token)
		m = token.match(/\A%([wWqQrsx])?(.)/)
		unless m
			format(token, :bad)
			return
		end
		good = token
		literal_type = m[1]
		pair_open = m[2]
		# TODO: resolve ambiguity with modulo operator
		index = PAIRS.transpose[0].index(pair_open)
		if index
			pair = PAIRS[index]
			# ignore escaped elements  %w(a\)b\\\)c)
			good_no_escapes = good.gsub(/\\\\/, '__').gsub(
				/\\[\(\)\{\}\[\]\<\>]/, '__')
			# we must do balancing
      definer_length = [literal_type, pair_open].join.length + 1 # 1 is the %
      definer = good.slice! 0, definer_length 
      format2(definer, :literal_definer)
			text1 = good
			text2 = nil
			re = Regexp.new("([" + 
				pair.map{|i|Regexp.escape(i)}.join + "])")
			result = good_no_escapes.balance_forward(
				re, pair.first, pair.last, 0)
			#x_y = good_no_escapes.paren_forward(0, pair)
			if result.kind_of?(Array) and result.last == 0
				#p "literal pair, x_y=#{result.inspect}"
				x, y = result
				text1 = good.slice!(0, x+1)
				text2 = good
				#lex_line_normal(good)
			else
				#p "literal propagating pair, x_y=#{result.inspect}"
				@states << State::Literal.new(literal_type, pair_open, result)
				format_end(:literal_end)
				#format(good, :literal)
			end
			#format(text1, :literal)
			case literal_type
			when 'q'
				format_literal(text1, false, pair[0], pair[1], '\\')
			when 'w'
				format_literal(text1, false, pair[0], pair[1], '\\', ' ')
			else
				format_literal(text1, true)
			end
			lex_line_normal(text2) if text2
		else
			# we don't have to do balancing
			text1 = good
			text2 = nil
			re = /\A(%[wWqQrsx]?(.))(?:[^\2\\\\]|[\\\\].)*?\2/
			m = re.match(good)
			if m
				#p "literal normal"
				text1 = good.slice!(0, m.end(0))
        definer = text1.slice!(0, m.end(1))
        format2(definer, :literal_definer)
				text2 = good
			else
				#p "literal propagating normal"
				@states << State::Literal.new(literal_type, pair_open, 1)
				format_end(:literal_end)
			end
			case literal_type
			when 'q'
				format_literal(text1, false, pair_open, '\\')
			when 'w'
				format_literal(text1, false, pair_open, '\\', ' ')
			else
				format_literal(text1, true)
			end
			lex_line_normal(text2) if text2
		end
	end
	def lex_line_normal(text)
		#print('N')
		tokens = tokenize(text)
		tokens.each do |bad, good|
			$logger.debug(2) { "processing bad=#{bad}  good=#{good}" }
			if bad
				format(bad, :bad) 
				next 
			end
			state = case good
			when /\A(=begin)(.*)/ # multiline comment
				# text before =begin is bad
				ok = @result.empty?
				# check if tailing text is bad
				ok = false if $~[2].match(/\A\S/)
				if ok
					@states << State::Comment.new
					format_end(:mcomment_end)
					format_comment(good, :mcomment, :mcomment_tab)
				end
				ok ? nil : :bad
			when /\A%/  # maybe division operator or regexp
				is_modulo = false
				@result.reverse_each do |(text, state)|
					case state 
					when :space, :tab   # skip blanks
						next
					when :number, :string, :ident, :dot, 
						:literal, :ivar, :cvar, :gvar
						is_modulo = true
					when :punct
						if text.match(/[\]\)]/)
							is_modulo = true
						end
					end
					break
				end

				if good.match(/\A%[\{]/)
					is_modulo = false
				end
				if good.match(/\A%[qQwWrsx][[:punct:]]/)
					is_modulo = false
				end

				if is_modulo
					$logger.debug(2) { "this is modulo" }
					format(good.slice!(0, 1), :punct)
					lex_line_normal(good)
					next
				end
 			
				token_literal(good)
				nil
			when /\A#/
				format_comment(good, :comment, :comment_tab)
				nil
			when /\A["'`]/ 
				quote_begin = $~.to_s
				m = /\A['"`](?:[^\\\\]|[\\\\].)*?(['"`]?)\z/.match(good)
				if m and quote_begin == m[1]
					# single line
				else
					# multi line
					@states << State::String.new(quote_begin)
					format_end((quote_begin == '`') ? :execute_end : :string_end)
				end
				format_string(
					good,
					quote_begin,
					(quote_begin == '`') ? :execute : :string,
					(quote_begin == '`') ? :execute1 : :string1,
					(quote_begin == '`') ? :execute_tab : :string_tab
				)
				nil
			when /\A\//  # maybe division operator or regexp
				is_division = false
				@result.reverse_each do |(text, state)|
					case state 
					when :space, :tab   # skip blanks
						next
					when :number, :ident, :dot, :ivar, :cvar, :gvar
						is_division = true
					when :punct
						if text.match(/[\]\)]/)
							is_division = true
						end
					when :keyword
						if text.match(/\Adef\z/)
							is_division = true
						end
					end
					break
				end

				#p "before good=#{good.inspect}"
				if is_division
					$logger.debug(2) { "this is division" }
					format(good.slice!(0, 1), :punct)
					lex_line_normal(good)
					next
				end

				if m = good.match(/\A(\/(?:[^\\\\]|[\\\\].)*?\/)(\w*)/)
					good.slice!(0, m[0].size)
					text1 = m[1]
					text2 = m[2]
					if text2.match(RE_REGEXP_OPTIONS)
						text1 << text2
						text2 = nil
					end
					format_string(text1, '/', :regexp, :regexp1, :regexp_tab)
					format(text2, :bad) if text2
					#p "calling text1=#{text1.inspect} good=#{good.inspect}"
					lex_line_normal(good)
				else
					@states << State::String.new('/')
					format_end(:regexp_end)
					format_string(good, '/', :regexp, :regexp1, :regexp_tab)
				end
				nil
			when /\A\.\w/
				:dot
			when /\A(\?)($|\s)/
				format($~[1], :punct)
				text = $~[2]
				format(text, (text=="\t") ? :tab : :space)
				nil
			when /\A[\d\?]/
				:number
			when RE_KEYWORD
				:keyword
			when /\A__END__(.)?/
				ok = !$~[1]
				ok = false unless @result.empty?
				@states << State::Endoffile.new if ok
				ok ? :endoffile : :bad
			when /\A\w/
				:ident
			when /\A:[[:alpha:]]/
				:symbol
			when /\A@[[:alpha:]]/
				:ivar
			when /\A@@[[:alpha:]]/
				:cvar
			when /\A\$\S+/
				:gvar
			when /\A\t/
				:tab
			when /\A\s/
				:space
			when /\A<<(-)?(["']?)([[:alpha:]_]\w*)(["']?)/
				m = $~
				ok = (m[2] == m[4])
				if ok
					ignore_leading_space = (m[1] != nil)
					interpolate = (m[2] != "'")
					begin_pattern = m[3]
					@states << State::Heredoc.new(
						begin_pattern, 
						ignore_leading_space,
						interpolate
					)
				end
				ok ? :heredoc : :bad
			when /\A[[:punct:]]/
				:punct
			else
				:any
			end
			format(good, state) if state
		end
	end
	def lex_line_heredoc(text)
		#print('H')
		state = @states[0]
		m = /\A(\s*)(\w+)$/.match(text)
		if m and m[2] == state.begin_tag
			ils = state.ignore_leading_spaces
			if ils or (!ils and m[1] == '')
				format_end(:heredoc_end2)
				format_heredoc(text, state.interpolate)
				@states.shift
				return
			end
		end
		format_end(:heredoc_end)
		format_heredoc(text, state.interpolate)
	end
	def lex_line_comment(text)
		#print('C')
		@states.shift if /\A(=end)(\s.*)?$/.match(text)
		format_end(:mcomment_end)
		format_comment(text, :mcomment, :mcomment_tab)
	end
	def lex_line_endoffile(text)
		format_end(:endoffile_end)
		format_comment(text, :endoffile, :endoffile_tab)
	end
	def lex_line_literal(text)
		state = @states[0]
		pair_open = state.symbol
		pair_close = pair_open
		
		# ignore escaped elements  %w(a\)b\\\)c)
		good_no_escapes = text.gsub(/\\\\/, '__').gsub(
			/\\./, '__')
		# we must do balancing
		length = nil
		index = PAIRS.transpose[0].index(state.symbol)
		if index
			# count pair, match when balance=0
			pair = PAIRS[index]
			pair_close = pair[1]
			re = Regexp.new("([" + 
				pair.map{|i|Regexp.escape(i)}.join + "])")
			result = good_no_escapes.balance_forward(
				re, pair.first, pair.last, state.balance)
			if result.kind_of?(Array)
				x, y = result
				length = x
			elsif result.kind_of?(Integer)
				# check balance
				if result != state.balance
					@states[0] = State::Literal.new(
						state.literal_type, state.symbol, result)
				end
			end
		else
			length = good_no_escapes.index(state.symbol)
		end
    text1 = text
    text2 = nil
		if length
			@states.shift
			text1 = text.slice!(0, length+1)
			text2 = text
    else
			format_end(:literal_end)
		end
		case state.literal_type
		when 'q'
			format_literal(text1, false, pair_open, pair_close, '\\')
		when 'w'
			format_literal(text1, false, pair_open, pair_close, '\\', ' ')
		else
			format_literal(text1, true)
		end
		lex_line_normal(text2) if text2
	end
	def lex_line_string(text)
		sym2state = {
			'\'' => :string,
			'"'  => :string,
			'/'  => :regexp,
			'`'  => :execute
		}
		sym2state.default = :bad

		state = @states[0]
		sym = sym2state[state.symbol]
		sym1 = (sym != :bad) ? (sym.to_s + "1").to_sym : :bad
		sym_tab = (sym != :bad) ? (sym.to_s + "_tab").to_sym : :bad
		
		sym2state_end = {
			'\'' => :string_end,
			'"'  => :string_end,
			'/'  => :regexp_end,
			'`'  => :execute_end
		}
		sym2state_end.default = :bad
		
		# ignore escaped elements  "a\"b\\\"c"
		good_no_escapes = text.gsub(/\\\\/, '__').gsub(
			/\\./, '__')
		if state.symbol == '/' 
			m = good_no_escapes.match(/\A.*?\/(\w*)/)
			if m
				@states.shift
				ok = m[1].match(RE_REGEXP_OPTIONS)
				text1 = ''
				text2 = nil
				unless ok
					# deal with  regexp/BAD     bad options
					text1 = text.slice!(0, m.begin(1))
					text2 = text.slice!(0, m[1].size)
				else
					text1 = text.slice!(0, m.end(0))
				end
				format_string(text1, state.symbol, sym, sym1, sym_tab)
				format(text2, :bad) if text2
				lex_line_normal(text)
	    	return
    	end
		end
		length = good_no_escapes.index(state.symbol)
		if length
			@states.shift
			text1 = text.slice!(0, length+1)
			format_string(text1, state.symbol, sym, sym1, sym_tab)
			lex_line_normal(text)
    	return
		end
		format_end(sym2state_end[state.symbol])
		format_string(text, state.symbol, sym, sym1, sym_tab)
	end
	def lex_line(text)
		if @states.empty? 
			return lex_line_normal(text) 
		end
		state = @states[0]
		case state
		when State::Heredoc: lex_line_heredoc(text)
		when State::Comment: lex_line_comment(text)
		when State::Endoffile: lex_line_endoffile(text)
		when State::Literal: lex_line_literal(text)
		when State::String: lex_line_string(text)
		else
			raise "unknown state #{state.class}"
		end
	end
end

end # module LexerRuby


if $0 == __FILE__
	#LexerRuby::LexerNew.profile
	LexerBase.benchmark
end
