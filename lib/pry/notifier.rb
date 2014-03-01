require "e2mmap"
require "pry/output-method"
module Pry
  # An output formatter used internally by the lexer.
  module Notifier
    def def_notifier(prefix = "", output_method = StdioOutputMethod.new)
      CompositeNotifier.new(prefix, output_method)
    end
    module_function :def_notifier

    class AbstractNotifier
      # Creates a new Notifier object
      attr_reader :prefix
      def initialize(prefix, base_notifier)
        @prefix = prefix
        @base_notifier = base_notifier
      end

      def notify?
        true
      end

      def puts(*objs)
        if notify?
          @base_notifier.puts(*objs.collect{|obj| prefix + obj.to_s})
        end
      end

      def ppx(prefix, *objs)
        if notify?
          @base_notifier.ppx @prefix+prefix, *objs
        end
      end

      def pp(*objs)
        if notify?
          @base_notifier.ppx @prefix, *objs
        end
      end
    end



    class CompositeNotifier<AbstractNotifier
      def initialize(prefix, base_notifier)
        super

        @notifiers = [D_NOMSG]
        @level_notifier = D_NOMSG
      end

      attr_reader :notifiers

      # Creates a new LeveledNotifier in the composite #notifiers group.
      #
      # The given +prefix+ will be assigned to the notifier, and +level+ will
      # be used as the index of the #notifiers Array.
      #
      # This method returns the newly created instance.
      def def_notifier(level, prefix = "")
        notifier = LeveledNotifier.new(self, level, prefix)
        @notifiers[level] = notifier
        notifier
      end
      attr_reader :level_notifier
      alias level level_notifier

      # Sets the leveled notifier for this object.
      #
      # When the given +value+ is an instance of AbstractNotifier,
      # #level_notifier is set to the given object.
      #
      # When an Integer is given, #level_notifier is set to the notifier at the
      # index +value+ in the #notifiers Array.
      #
      # If no notifier exists at the index +value+ in the #notifiers Array, an
      # ErrUndefinedNotifier exception is raised.
      #
      # An ErrUnrecognizedLevel exception is raised if the given +value+ is not
      # found in the existing #notifiers Array, or an instance of
      # AbstractNotifier
      def level_notifier=(value)
        case value
          when AbstractNotifier
            @level_notifier = value
          when Integer
            l = @notifiers[value]
            Notifier.Raise ErrUndefinedNotifer, value unless l
            @level_notifier = l
          else
            Notifier.Raise ErrUnrecognizedLevel, value unless l
        end
      end

      alias level= level_notifier=
    end

    class LeveledNotifier<AbstractNotifier
      include Comparable

      # Create a new leveled notifier with the given +base+, and +prefix+ to
      # send to AbstractNotifier.new
      #
      # The given +level+ is used to compare other leveled notifiers in the
      # CompositeNotifier group to determine whether or not to output
      # notifications.
      def initialize(base, level, prefix)
        super(prefix, base)

        @level = level
      end

      # The current level of this notifier object
      attr_reader :level

      # Compares the level of this notifier object with the given +other+
      # notifier.
      #
      # See the Comparable module for more information.
      def <=>(other)
        @level <=> other.level
      end

      # Whether to output messages to the output method, depending on the level
      # of this notifier object.
      def notify?
        @base_notifier.level >= self
      end
    end

    class NoMsgNotifier<LeveledNotifier
      # Creates a new notifier that should not be used to output messages.
      def initialize
        @base_notifier = nil
        @level = 0
        @prefix = ""
      end

      def notify?
        false
      end
    end
    D_NOMSG = NoMsgNotifier.new
  end
end