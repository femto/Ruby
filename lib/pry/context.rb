require "pry/workspace"
require "irb/inspector"

module Pry
  # A class that wraps the current state of the irb session, including the
  # configuration of IRB.conf.
  class Context
    attr_accessor :inspect_mode,:math_mode,:use_tracer,:eval_history,:prompt_mode,:use_readline,:debug_level
    attr_accessor :io, :prompt_i,:prompt_s,:prompt_c,:prompt_n,:auto_indent_mode

    # Alias for #use_readline
    alias use_readline? use_readline
    # Alias for #rc
    #alias rc? rc
    #alias ignore_sigint? ignore_sigint
    #alias ignore_eof? ignore_eof
    #alias echo? echo
    def initialize(session, workspace = nil, input_method = nil, output_method = nil)
      @session = session
      if workspace
        @workspace = workspace
      else
        @workspace = WorkSpace.new
      end
      @thread = Thread.current if defined? Thread
      #@pry_level = 0

      # copy of default configuration
      @ap_name = Pry.conf[:AP_NAME]
      @rc = Pry.conf[:RC]
      @load_modules = Pry.conf[:LOAD_MODULES]

      @use_readline = Pry.conf[:USE_READLINE]
      @verbose = Pry.conf[:VERBOSE]
      @io = nil

      self.inspect_mode = Pry.conf[:INSPECT_MODE]
      self.math_mode = Pry.conf[:MATH_MODE] if Pry.conf[:MATH_MODE]
      self.use_tracer = Pry.conf[:USE_TRACER] if Pry.conf[:USE_TRACER]
      self.use_loader = Pry.conf[:USE_LOADER] if Pry.conf[:USE_LOADER]
      self.eval_history = Pry.conf[:EVAL_HISTORY] if Pry.conf[:EVAL_HISTORY]

      @ignore_sigint = Pry.conf[:IGNORE_SIGINT]
      @ignore_eof = Pry.conf[:IGNORE_EOF]

      @back_trace_limit = Pry.conf[:BACK_TRACE_LIMIT]

      self.prompt_mode = Pry.conf[:PROMPT_MODE]

      if Pry.conf[:SINGLE_IRB] or !defined?(Pry::JobManager)
        @pry_name = Pry.conf[:PRY_NAME]
      else
        @pry_name = Pry.conf[:PRY_NAME]+"#"+Pry.JobManager.n_jobs.to_s
      end
      @pry_path = "(" + @pry_name.to_s + ")"

      case input_method
        when nil
          case use_readline?
            when nil
              if (defined?(ReadlineInputMethod) && STDIN.tty? &&
                  Pry.conf[:PROMPT_MODE] != :INF_RUBY)
                @io = ReadlineInputMethod.new
              else
                @io = StdioInputMethod.new
              end
            when false
              @io = StdioInputMethod.new
            when true
              if defined?(ReadlineInputMethod)
                @io = ReadlineInputMethod.new
              else
                @io = StdioInputMethod.new
              end
          end

        when String
          @io = FileInputMethod.new(input_method)
          @pry_name = File.basename(input_method)
          @pry_path = input_method
        else
          @io = input_method
      end
      self.save_history = Pry.conf[:SAVE_HISTORY] if Pry.conf[:SAVE_HISTORY]

      if output_method
        @output_method = output_method
      else
        @output_method = StdioOutputMethod.new
      end

      @echo = Pry.conf[:ECHO]
      if @echo.nil?
        @echo = true
      end
      self.debug_level = Pry.conf[:DEBUG_LEVEL]
    end

    def main
      @workspace.main
    end

    def prompting?
      verbose? || (STDIN.tty? && @io.kind_of?(StdioInputMethod) ||
          (defined?(ReadlineInputMethod) && @io.kind_of?(ReadlineInputMethod)))
    end

    def prompt_mode=(mode)
      @prompt_mode = mode
      pconf = Pry.conf[:PROMPT][mode]
      @prompt_i = pconf[:PROMPT_I]
      @prompt_s = pconf[:PROMPT_S]
      @prompt_c = pconf[:PROMPT_C]
      @prompt_n = pconf[:PROMPT_N]
      @return_format = pconf[:RETURN]
      if ai = pconf.include?(:AUTO_INDENT)
        @auto_indent_mode = ai
      else
        @auto_indent_mode = Pry.conf[:AUTO_INDENT]
      end
    end

    def verbose?
      if @verbose.nil?
        if defined?(ReadlineInputMethod) && @io.kind_of?(ReadlineInputMethod)
          false
        elsif !STDIN.tty? or @io.kind_of?(FileInputMethod)
          true
        else
          false
        end
      else
        @verbose
      end
    end
  end
end