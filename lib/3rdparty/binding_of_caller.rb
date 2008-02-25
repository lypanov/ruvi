begin
  require 'simplecc'
rescue LoadError
  def Continuation.create(*args, &block)
    cc = nil; result = callcc {|c| cc = c; block.call(cc) if block and args.empty?}
    result ||= args
    return *[cc, *result]
  end
end

# This method returns the binding of the method that called your
# method. It will raise an Exception when you're not inside a method.
#
# It's used like this:
#   def inc_counter
#     Binding.of_caller do |binding|
#       eval("counter += 1", binding)
#     end
#   end
#   counter = 0
#   2.times { inc_counter }
#   counter # => 2
#
# You will have to put the whole rest of your method into the
# block that you pass into this method. If you don't do this
# an Exception will be raised. Because of the way that this is
# implemented it has to be done this way. If you don't do it
# like this it will raise an Exception.
def Binding.of_caller(&block)
  old_critical = Thread.critical
  Thread.critical = true
  count = 0
  cc, result, error, extra_data = Continuation.create(nil, nil)
  error.call if error

  tracer = lambda do |*args|
    type, context, extra_data = args[0], args[4], args
    if type == "return"
      count += 1
      # First this method and then calling one will return --
      # the trace event of the second event gets the context
      # of the method which called the method that called this
      # method.
      if count == 2
        # It would be nice if we could restore the trace_func
        # that was set before we swapped in our own one, but
        # this is impossible without overloading set_trace_func
        # in current Ruby.
        set_trace_func(nil)
        cc.call(eval("binding", context), nil, extra_data)
      end
    elsif type != "line"
      set_trace_func(nil)
      error_msg = "Binding.of_caller used in non-method context or " +
        "trailing statements of method using it aren't in the block."
      cc.call(nil, lambda { raise(ArgumentError, error_msg) }, nil)
    end
  end

  unless result
    set_trace_func(tracer)
    return nil
  else
    Thread.critical = old_critical
    case block.arity
      when 1 then yield(result)
      else yield(result, extra_data)        
    end
  end
end
