module Pry
  STDIN_FILE_NAME = "(line)" # :nodoc:
  class InputMethod
    attr_accessor :prompt
  end
  class StdioInputMethod < InputMethod

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