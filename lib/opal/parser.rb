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

      @yydebug = true

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

    #def new_paren(open, expr, close)
    #  if expr.nil? or expr == [:block]
    #    s1(:paren, s0(:nil, source(open)), source(open))
    #  else
    #    s1(:paren, expr, source(open))
    #  end
    #end

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

    def new_break(kw, args=nil)
      if args.nil?
        sexp = s(:break)
      elsif args.length == 1
        sexp = s(:break, args[0])
      else
        sexp = s(:break, s(:array, *args))
      end

      sexp
    end

    def new_body(compstmt, res, els, ens)
      s = compstmt || s(:block)

      if res
        s = s(:rescue, s)
        res.each { |r| s << r }
        s << els if els
      end

      ens ? s(:ensure, s, ens) : s
    end

    def new_const(tok)
      s1(:const, value(tok).to_sym, source(tok))
    end

    def new_call(recv, meth, args = nil)
      args ||= []
      sexp = s(:call, recv, value(meth).to_sym, s(:arglist, *args))
      sexp.source = source(meth)
      sexp
    end

    def new_binary_call(recv, meth, arg)
      new_call(recv, meth, [arg])
    end

    def new_unary_call(op, recv)
      new_call(recv, op, [])
    end



    def new_assignable(ref)
      case ref.type
        when :ivar
          ref.type = :iasgn
        when :const
          ref.type = :cdecl
        when :identifier
          scope.add_local ref[1] unless scope.has_local? ref[1]
          ref.type = :lasgn
        when :gvar
          ref.type = :gasgn
        when :cvar
          ref.type = :cvdecl
        else
          raise "Bad new_assignable type: #{ref.type}"
      end

      ref
    end

    def add_block_pass(arglist, block)
      arglist << block if block
      arglist
    end

    def new_splat(tok, value)
      s1(:splat, value, source(tok))
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

    def new_regexp(reg, ending)
      return s(:regexp, '') unless reg
      case reg.type
        when :str
          s(:regexp, reg[1], value(ending))
        when :evstr
          s(:dregx, "", reg)
        when :dstr
          reg.type = :dregx
          reg
      end
    end

    def str_append(str, str2)
      return str2 unless str
      return str unless str2

      if str.type == :evstr
        str = s(:dstr, "", str)
      elsif str.type == :str
        str = s(:dstr, str[1])
      else
        #puts str.type
      end
      str << str2
      str
    end

    def new_str_content(tok)
      s1(:str, value(tok), source(tok))
    end
  end
end