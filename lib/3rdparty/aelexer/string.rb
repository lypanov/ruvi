class String
	def paren_backward(balance=0, pair=nil, &block)
		pair ||= ['(', ')']
		return nil if balance == 0 and not self.include?(pair.last)
		re = Regexp.new("([" + pair.map{|i|Regexp.escape(i)}.join + "])")
		result = balance_backward(
			re,
			pair.first,
			pair.last,
			balance,
			&block
		)
		return result if result.kind_of?(Array)
		nil  # otherwise ignore balance 
	end
	# return types
	# match..... Array  = [x, y] position
	# mismatch.. Fixnum = balance
	def balance_backward(re, pair_open, pair_close, balance=0, &block)
		s = self
		y = 0
		while s
			$logger.debug(2) { "str=#{s.inspect}   bal=#{balance}" }
			x = s.size
			s.split(re).reverse_each do |token|
				x -= token.size
				case token
				when pair_close
					balance += 1
				when pair_open
					balance -= 1
					return balance if balance < 0
					return [x, y] if balance == 0
				end
			end
			return balance unless block_given?
			y -= 1
			s = block.call(y)
		end # loop
		balance
	end
	def paren_forward(balance=0, pair=nil, &block)
		pair ||= ['(', ')']
		$logger.debug(2) { "forward  pair=#{pair.inspect}  str=#{self.inspect}" }
		return nil if balance == 0 and not self.include?(pair.first)
		re = Regexp.new("([" + pair.map{|i|Regexp.escape(i)}.join + "])")
		result = self.balance_forward(
			re,
			pair.first,
			pair.last,
			balance,
			&block
		)
		return result if result.kind_of?(Array)
		nil  # otherwise ignore balance 
	end
	# return types
	# match..... Array  = [x, y] position
	# mismatch.. Fixnum = balance
	def balance_forward(re, pair_open, pair_close, balance=0, &block)
		s = self
		y = 0
		while s
			$logger.debug(2) { "str=#{s.inspect}   bal=#{balance}" }
			x = 0
			# TODO: split is inefficient.. use scan
			s.split(re).each do |token|
				case token
				when pair_open
					balance += 1
				when pair_close
					balance -= 1
					return balance if balance < 0
					return [x, y] if balance == 0
				end
				x += token.size
			end
			return balance unless block_given?
			y += 1
			s = block.call(y)
		end # loop
		balance
	end
	def expand_tabs(tabsize)
		res = ""
		self.split(/(\t)/).each do |txt|
			if txt == "\t"
				n = tabsize - (res.size % tabsize)
				res << ("\t" * n)
			else
				res << txt
			end
		end
		res
	end
	def match_bracket(position, &block)
		pairs = [%w|( )|, %w|[ ]|, %w|< >|, %w|{ }|]
		
		str_right = self[position, self.size-position]		
		re_right = Regexp.new(
			'\A[^' +
			pairs.flatten.map{|i|Regexp.escape(i)}.join +
			']*([' +
			pairs.transpose[1].map{|i|Regexp.escape(i)}.join +
			'])'
		)
		match_right = str_right.match(re_right)
		bal_right = match_right ? 1 : 0
		
		str_left = self[0, position]
		re_left = Regexp.new(
			'([' +
			pairs.transpose[0].map{|i|Regexp.escape(i)}.join +
			'])[^' +
			pairs.flatten.map{|i|Regexp.escape(i)}.join +
			']*\z'
		)
		match_left = str_left.match(re_left)
		bal_left = match_left ? 1 : 0
		
		$logger.debug(2) { "#{str_left.inspect} (#{bal_left} - " + 
			"#{bal_right}) #{str_right.inspect}"}

		# determine what to search for
		symb_left = nil
		symb_right = nil
		pair_n_left = nil
		pair_n_right = nil
		if match_right
			symb_right = match_right[1]
			pair_n_right = pairs.transpose[1].index(symb_right)
		end
		if match_left
			symb_left = match_left[1]
			pair_n_left = pairs.transpose[0].index(symb_left)
		end
		pair_n = pair_n_right || pair_n_left
		pair = nil
		pair = pairs[pair_n] if pair_n
		$logger.debug(2) { "input=\"#{str_left}  #{str_right}\"  " + 
			"left=#{symb_left.inspect} " +
			"right=#{symb_right.inspect} " +
			"pair=#{pair.inspect}" }
			
		# look for matching close parentesis
		re_reset = Regexp.new(
			'[' +
			pairs.flatten.map{|i|Regexp.escape(i)}.join +
			']'
		)
		if str_right.match(re_reset)
			$logger.debug(2) { "reseting left balance" }
			bal_left = 0
		end
		pair1 = pair
		unless pair1
=begin
			re = Regexp.new(
				'\A[^' +
				pairs.transpose[0].map{|i|Regexp.escape(i)}.join +
				']*([' +
				pairs.transpose[0].map{|i|Regexp.escape(i)}.join +
				'])'
			)
			m = str_right.match(re)
			if m
				pair1 = pairs[pairs.transpose[0].index(m[1])]
				$logger.debug(1) { "forward with pair #{pair1.inspect}"}
=end
				re = Regexp.new(
					'[' +
					pairs.transpose[0].map{|i|Regexp.escape(i)}.join +
					']'
				)
				$logger.debug(2) { "reg = #{re.source}" }
				m2 = str_right.match(re)
				if m2
					pair1 = pairs[pairs.transpose[0].index(m2.to_s)]
					$logger.debug(2) { "forward with better pair #{pair1.inspect}" }
				end
			#end
		end
		location = str_right.paren_forward(bal_left, pair1, &block)
		if location
			x, y = location
			x += position if y == 0
			if y != 0 or (y == 0 and x != position)
				$logger.debug(2) { "forward match at (#{x},#{y})" }
				return [y, x]
			else
				$logger.debug(2) { "canceling match" }
			end
		else
			$logger.debug(2) { "no forward match" }
		end
		re_bailout = Regexp.new(
			'\A[^' + 
			pairs.transpose[1].map{|i|Regexp.escape(i)}.join +
			']*[' +
			pairs.transpose[0].map{|i|Regexp.escape(i)}.join +
			']'
		)
		#return nil if str_right.match(/\A[^\)]*\(/)
		if str_right.match(re_bailout)
			$logger.debug(2) { "bailout" }
			return nil
		end
		# look for matching open parentesis
		pair2 = pair
		unless pair2
			re = Regexp.new(
				'([' +
				pairs.transpose[1].map{|i|Regexp.escape(i)}.join +
				'])[^' +
				pairs.transpose[1].map{|i|Regexp.escape(i)}.join +
				']*\z'
			)
			m = str_left.match(re)
			if m
				pair2 = pairs[pairs.transpose[1].index(m[1])]
				$logger.debug(2) { "found backward pair #{pair2.inspect}" }
			end
		end
		location = str_left.paren_backward(bal_right, pair2, &block)
		if location
			x, y = location
			$logger.debug(2) { "backward match at (#{x},#{y})" }
			return [y, x]
		end
		$logger.debug(2) { "no match" }
		nil
	end
end
