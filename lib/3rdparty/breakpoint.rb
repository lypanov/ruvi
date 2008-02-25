require 'irb'
require '3rdparty/binding_of_caller'

module IRB
  def IRB.start(ap_path = nil, main_context = nil)
    $0 = File::basename(ap_path, ".rb") if ap_path

    # suppress some warnings about redefined constants
    old_verbose, $VERBOSE = $VERBOSE, nil
    IRB.setup(ap_path)
    $VERBOSE = old_verbose

    if @CONF[:SCRIPT]
      irb = Irb.new(main_context, @CONF[:SCRIPT])
    else
      irb = Irb.new(main_context)
    end

    @CONF[:IRB_RC].call(irb.context) if @CONF[:IRB_RC]
    @CONF[:MAIN_CONTEXT] = irb.context

    trap("SIGINT") do
      irb.signal_handle
    end
    
    catch(:IRB_EXIT) do
      irb.eval_input
    end
  end
end

# This will pop up an interactive ruby session at a
# pre-defined break point in a Ruby application. In
# this session you can examine the environment of
# the break point.
#
# You can get a list of variables in the context using
# local_variables via +local_variables+. You can then
# examine their values by typing their names.
#
# You can have a look at the call stack via +caller+.
#
# breakpoints can also return a value. They will execute
# a supplied block for getting a default return value.
# A custom value can be returned from the session by doing
# +throw(:debug_return, value)+.
#
# You can also give names to break points which will be
# used in the message that is displayed upon execution 
# of them.
#
# Here's a sample of how breakpoints should be placed:
#
#   class Person
#     def initialize(name, age)
#       @name, @age = name, age
#       breakpoint("Person#initialize")
#     end
#
#     attr_reader :age
#     def name
#       breakpoint("Person#name") { @name }
#     end
#   end
#
#   person = Person.new("Random Person", 23)
#   puts "Name: #{person.name}"
#
# And here is a sample debug session:
#
#   Executing break point "Person#initialize" at file.rb:4 in `initialize'
#   irb(#<Person:0x292fbe8>):001:0> local_variables
#   => ["name", "age", "_", "__"]
#   irb(#<Person:0x292fbe8>):002:0> [name, age]
#   => ["Random Person", 23]
#   irb(#<Person:0x292fbe8>):003:0> [@name, @age]
#   => ["Random Person", 23]
#   irb(#<Person:0x292fbe8>):004:0> self
#   => #<Person:0x292fbe8 @age=23, @name="Random Person">
#   irb(#<Person:0x292fbe8>):005:0> @age += 1; self
#   => #<Person:0x292fbe8 @age=24, @name="Random Person">
#   irb(#<Person:0x292fbe8>):006:0> exit
#   Executing break point "Person#name" at file.rb:9 in `name'
#   irb(#<Person:0x292fbe8>):001:0> throw(:debug_return, "Overriden name")
#   Name: Overriden name
def breakpoint(id = nil, context = nil, &block)
  file, line, method = *caller.first.match(/^(.+?):(\d+)(?::in `(.*?)')?/).captures
  body = lambda do |_context|
    msg = "Executing break point " + (id ? "#{id.inspect} " : "") +
          "at #{file}:#{line}" + (method ? " in `#{method}'" : "")
    puts msg
    catch(:debug_return) do |value|
      IRB.start(nil, IRB::WorkSpace.new(_context))
      block.call if block        
    end
  end

  return body.call(context) if context
  Binding.of_caller do |binding_context|
    body.call(binding_context)
  end
end
alias :break_point :breakpoint

if $DEBUG or not $OPTIMIZE_ASSERTS
  # This asserts that the block evaluates to true.
  # If it doesn't evaluate to true a breakpoint will
  # automatically be created at that execution point.
  #
  # You can disable assert checking by setting the
  # global variable $OPTIMIZE_ASSERTS to true before
  # loading the breakpoint.rb library. (It will still
  # be enabled when Ruby is run via the -d argument.)
  #
  # Example:
  #   person_name = "Foobar"
  #   assert { not person_name.nil? }
  def assert(&condition)
    unless yield
      file, line, method = *caller.first.match(/^(.+?):(\d+)(?::in `(.*?)')?/).captures
      Binding.of_caller do |context|
        puts "Assert failed at #{file}:#{line}#{" in `#{method}'" if method}"
        breakpoint(nil, context)
      end
    end
  end
else
  def assert(&condition); end
end
