require 'pry/src_encoding'
require 'pry/magic-file'
module Pry
  STDIN_FILE_NAME = "(line)" # :nodoc:
  class InputMethod
    attr_accessor :prompt

    def initialize(file = STDIN_FILE_NAME)
      @file_name = file
    end
    def readable_after_eof?
      false
    end

    def gets
      IRB.fail NotImplementedError, "gets"
    end
    public :gets
  end
  class StdioInputMethod < InputMethod

    def initialize
      super
      @line_no = 0
      @line = []
      @stdin = IO.open(STDIN.to_i, :external_encoding => Pry.conf[:LC_MESSAGES].encoding, :internal_encoding => "-")
      @stdout = IO.open(STDOUT.to_i, 'w', :external_encoding => Pry.conf[:LC_MESSAGES].encoding, :internal_encoding => "-")
    end

    def gets
      print @prompt
      line = @stdin.gets
      @line[@line_no += 1] = line
    end

    def readable_after_eof?
      true
    end
  end
  class FileInputMethod < InputMethod

  end
  begin
    require "readline"
    class ReadlineInputMethod < InputMethod
      include Readline
    end
  rescue
  end
end