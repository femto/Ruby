require "e2mmap"

module Pry
  # An abstract output class for IO in irb. This is mainly used internally by
  # IRB::Notifier. You can define your own output method to use with Irb.new,
  # or Context.new
  class OutputMethod

    def puts(*objs)
      for obj in objs
        print(*obj)
        print "\n"
      end
    end

    def pp(*objs)
      puts(*objs.collect{|obj| obj.inspect})
    end

    # Prints the given +objs+ calling Object#inspect on each and appending the
    # given +prefix+.
    #
    # See #puts for more detail.
    def ppx(prefix, *objs)
      puts(*objs.collect{|obj| prefix+obj.inspect})
    end

  end
  class StdioOutputMethod<OutputMethod
    # Prints the given +opts+ to standard output, see IO#print for more
    # information.
    def print(*opts)
      STDOUT.print(*opts)
    end
  end
end
