module Pry # :nodoc:
  class WorkSpace
    attr_reader :main

    def initialize(*main)
      if main[0].kind_of?(Binding)
        @binding = main.shift
      elsif Pry.conf[:SINGLE_IRB]
        @binding = TOPLEVEL_BINDING
      else
        case Pry.conf[:CONTEXT_MODE]
          when 0	# binding in proc on TOPLEVEL_BINDING
            @binding = eval("proc{binding}.call",
                            TOPLEVEL_BINDING,
                            __FILE__,
                            __LINE__)
          when 1	# binding in loaded file
            require "tempfile"
            f = Tempfile.open("irb-binding")
            f.print <<EOF
	  $binding = binding
EOF
            f.close
            load f.path
            @binding = $binding

          when 2	# binding in loaded file(thread use)
            unless defined? BINDING_QUEUE
              require "thread"

              IRB.const_set(:BINDING_QUEUE, SizedQueue.new(1))
              Thread.abort_on_exception = true
              Thread.start do
                eval "require \"irb/ws-for-case-2\"", TOPLEVEL_BINDING, __FILE__, __LINE__
              end
              Thread.pass
            end
            @binding = BINDING_QUEUE.pop

          when 3	# binging in function on TOPLEVEL_BINDING(default)
            @binding = eval("def irb_binding; private; binding; end; irb_binding",
                            TOPLEVEL_BINDING,
                            __FILE__,
                            __LINE__ - 3)
        end
      end
      if main.empty?
        @main = eval("self", @binding)
      else
        @main = main[0]
        Pry.conf[:__MAIN__] = @main
        case @main
          when Module
            @binding = eval("IRB.conf[:__MAIN__].module_eval('binding', __FILE__, __LINE__)", @binding, __FILE__, __LINE__)
          else
            begin
              @binding = eval("IRB.conf[:__MAIN__].instance_eval('binding', __FILE__, __LINE__)", @binding, __FILE__, __LINE__)
            rescue TypeError
              Pry.fail CantChangeBinding, @main.inspect
            end
        end
      end
      eval("_=nil", @binding)
    end
  end
end
