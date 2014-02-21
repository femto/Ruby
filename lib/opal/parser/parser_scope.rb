module Opal
  # ParserScope is used during lexing to keep track of local variables
  # created inside a scope. A lexer scope can be asked if it has a local
  # variable defined, and it can also check its parent scope if applicable.
  class ParserScope
    attr_reader :locals
    attr_accessor :parent
    def initialize(type)
      @block  = type == :block
      @locals = []
      @parent = nil
    end

  end
end