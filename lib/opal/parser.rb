require 'opal/parser/sexp'
require 'opal/parser/lexer'
require 'opal/parser/grammar'
require 'opal/parser/parser_scope'


module Opal
  class Parser < Racc::Parser
    attr_reader :lexer
    def parse(source, file = '(string)')
      @file = file
      @scopes = []
      @lexer = Lexer.new(source, file)
      @lexer.parser = self

      self.parse_to_sexp
    end

    def parse_to_sexp
      push_scope
      result = do_parse
      pop_scope

      result
    end

    def next_token
      @lexer.next_token
    end

    def s(*parts)
      Sexp.new(parts)
    end

    def push_scope(type = nil)
      top = @scopes.last
      scope = ParserScope.new type
      scope.parent = top
      @scopes << scope
      @scope = scope
    end

    def pop_scope
      @scopes.pop
      @scope = @scopes.last
    end

    def value(tok)
      tok[0]
    end

    def source(tok)
      tok ? tok[1] : nil
    end

    def s1(type, first, source)
      sexp = s(type, first)
      sexp.source = source
      sexp
    end

    def new_compstmt(block)
      comp = if block.size == 1
               nil
             elsif block.size == 2
               block[1]
             else
               block
             end

      if comp && comp.type == :begin && comp.size == 2
        result = comp[1]
      else
        result = comp
      end

      result
    end

    def new_block(stmt = nil)
      sexp = s(:block)
      sexp << stmt if stmt
      sexp
    end

    def new_alias(kw, new, old)
      sexp = s(:alias, new, old)
      sexp.source = source(kw)
      sexp
    end

    def new_sym(tok)
      s1(:sym, value(tok).to_sym, source(tok))
    end
  end
end