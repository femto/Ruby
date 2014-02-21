require 'opal/parser/sexp'
require 'opal/parser/lexer'
require 'opal/parser/grammar'
require 'opal/parser/parser_scope'


module Opal
  class Parser < Racc::Parser
    attr_reader :lexer, :scope
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

    def s0(type, source)
      sexp = s(type)
      sexp.source = source
      sexp
    end

    def s1(type, first, source)
      sexp = s(type, first)
      sexp.source = source
      sexp
    end

    def op_to_setter(op)
      "#{value(op)}=".to_sym
    end

    def new_ident(tok)
      s1(:identifier, value(tok).to_sym, source(tok))
    end

    def new_ivar(tok)
      s1(:ivar, value(tok).to_sym, source(tok))
    end

    def new_attrasgn(recv, op, args=[])
      arglist = s(:arglist, *args)
      sexp = s(:attrasgn, recv, op, arglist)
      sexp
    end

    def new_assign(lhs, tok, rhs)
      case lhs.type
        when :iasgn, :cdecl, :lasgn, :gasgn, :cvdecl, :nth_ref
          lhs << rhs
          lhs
        when :call, :attrasgn
          lhs.last << rhs
          lhs
        when :colon2
          lhs << rhs
          lhs.type = :casgn
          lhs
        when :colon3
          lhs << rhs
          lhs.type = :casgn3
          lhs
        else
          raise "Bad lhs for new_assign: #{lhs.type}"
      end
    end

    def new_var_ref(ref)
      case ref.type
        when :self, :nil, :true, :false, :line, :file
          ref
        when :const
          ref
        when :ivar, :gvar, :cvar
          ref
        when :int
          # this is when we passed __LINE__ which is converted into :int
          ref
        when :str
          # returns for __FILE__ as it is converted into str
          ref
        when :identifier
          result = if scope.has_local? ref[1]
                     s(:lvar, ref[1])
                   else
                     s(:call, nil, ref[1], s(:arglist))
                   end

          result.source = ref.source
          result
        else
          raise "Bad var_ref type: #{ref.type}"
      end
    end

    def new_int(tok)
      s1(:int, value(tok), source(tok))
    end

    def new_and(lhs, tok, rhs)
      sexp = s(:and, lhs, rhs)
      sexp.source = source(tok)
      sexp
    end

    def new_self(tok)
      s0(:self, source(tok))
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