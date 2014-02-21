module Opal
  class Sexp
    attr_accessor :source
    def initialize(args)
      @array = args
    end

    def type
      @array[0]
    end

    def type=(type)
      @array[0] = type
    end

    def <<(other)
      @array << other
      self
    end

    def method_missing(sym, *args, &block)
      @array.send sym, *args, &block
    end

    def ==(other)
      if other.is_a? Sexp
        @array == other.array
      else
        @array == other
      end
    end

    alias eql? ==

  end
end