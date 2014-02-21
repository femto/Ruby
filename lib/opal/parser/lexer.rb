require 'opal/parser/keywords'
module Opal
  class Lexer
    attr_reader :line
    attr_reader :scope
    attr_reader :eof_content

    attr_accessor :lex_state
    attr_accessor :strterm
    attr_accessor :scanner
    attr_accessor :yylval
    attr_accessor :parser
    def initialize(source, file)
      @lex_state  = :expr_beg
      @cond       = 0
      @cmdarg     = 0
      @line       = 1
      @tok_line   = 1
      @column     = 0
      @tok_column = 0
      @file       = file

      @scanner = StringScanner.new(source)
      @scanner_stack = [@scanner]
    end

    def next_token
      token     = self.yylex
      value     = self.yylval
      location  = [@tok_line, @tok_column]

      # once location is stored, ensure next token starts in correct place
      @tok_column = @column
      @tok_line = @line

      [token, [value, location]]
    end

    def scan(regexp)
      if result = @scanner.scan(regexp)
        @column += result.length
        @yylval += @scanner.matched
      end

      result
    end

    def check(regexp)
      @scanner.check regexp
    end

    def after_operator?
      [:expr_fname, :expr_dot].include? @lex_state
    end

    def beg?
      [:expr_beg, :expr_value, :expr_mid, :expr_class].include? @lex_state
    end

    def end?
      [:expr_end, :expr_endarg, :expr_endfn].include? @lex_state
    end

    def spcarg?
      arg? and @space_seen and !space?
    end

    def space?
      @scanner.check(/\s/)
    end

    def arg?
      [:expr_arg, :expr_cmdarg].include? @lex_state
    end

    def cond_push(n)
      @cond = (@cond << 1) | (n & 1)
    end

    def cmdarg_push(n)
      @cmdarg = (@cmdarg << 1) | (n & 1)
    end

    def cond_lexpop
      @cond = (@cond >> 1) | (@cond & 1)
    end

    def cmdarg_lexpop
      @cmdarg = (@cmdarg >> 1) | (@cmdarg & 1)
    end

    def set_arg_state
      @lex_state = after_operator? ? :expr_arg : :expr_beg
    end


    def skip(regexp)
      if result = @scanner.scan(regexp)
        @column += result.length
        @tok_column = @column
      end

      result
    end


    def yylex
      @yylval = ''
      @space_seen = false
      cmd_start = false
      c = ''

      if self.strterm
        if self.strterm[:type] == :heredoc
          token = here_document(self.strterm)
        else
          token = parse_string
        end

        if token == :tSTRING_END or token == :tREGEXP_END
          self.strterm = nil
          @lex_state = :expr_end
        end

        return token
      end

      while true
        if skip(/\ |\t|\r/)
          @space_seen = true
          next

        elsif skip(/(\n|#)/)
          c = scanner.matched
          if c == '#'
            skip(/(.*)/)
          else
            self.line += 1
          end

          skip(/(\n+)/)

          if scanner.matched
            self.line += scanner.matched.length
          end

          next if [:expr_beg, :expr_dot].include? @lex_state

          if skip(/([\ \t\r\f\v]*)\./)
            @space_seen = true unless scanner[1].empty?
            pushback(1)

            next unless check(/\.\./)
          end

          cmd_start = true
          @lex_state = :expr_beg
          self.yylval = '\\n'
          return :tNL

        elsif scan(/\;/)
          @lex_state = :expr_beg
          return :tSEMI

        elsif check(/\*/)
          if scan(/\*\*\=/)
            @lex_state = :expr_beg
            return new_op_asgn('**')
          elsif scan(/\*\*/)
            self.set_arg_state
            return :tPOW
          elsif scan(/\*\=/)
            @lex_state = :expr_beg
            return new_op_asgn('*')
          else
            scan(/\*/)

            if after_operator?
              @lex_state = :expr_arg
              return :tSTAR2
            elsif @space_seen && check(/\S/)
              @lex_state = :expr_beg
              return :tSTAR
            elsif [:expr_beg, :expr_mid].include? @lex_state
              @lex_state = :expr_beg
              return :tSTAR
            else
              @lex_state = :expr_beg
              return :tSTAR2
            end
          end

        elsif scan(/\!/)
          if after_operator?
            @lex_state = :expr_arg
            if scan(/@/)
              return :tBANG, '!'
            end
          else
            @lex_state = :expr_beg
          end

          if scan(/\=/)
            return :tNEQ
          elsif scan(/\~/)
            return :tNMATCH
          end

          return :tBANG

        elsif scan(/\=/)
          if @lex_state == :expr_beg and !@space_seen
            if scan(/begin/) and space?
              scan(/(.*)/) # end of line
              line_count = 0

              while true
                if scanner.eos?
                  raise "embedded document meets end of file"
                end

                if scan(/\=end/) and space?
                  @line += line_count
                  return yylex
                end

                if scan(/\n/)
                  line_count += 1
                  next
                end

                scan(/(.*)/)
              end
            end
          end

          self.set_arg_state

          if scan(/\=/)
            if scan(/\=/)
              return :tEQQ
            end

            return :tEQ
          end

          if scan(/\~/)
            return :tMATCH
          elsif scan(/\>/)
            return :tASSOC
          end

          return :tEQL

        elsif scan(/\"/)
          self.strterm = new_strterm(STR_DQUOTE, '"', "\0")
          return :tSTRING_BEG

        elsif scan(/\'/)
          self.strterm = new_strterm(STR_SQUOTE, "'", "\0")
          return :tSTRING_BEG

        elsif scan(/\`/)
          self.strterm = new_strterm(STR_XQUOTE, "`", "\0")
          return :tXSTRING_BEG

        elsif scan(/\&/)
          if scan(/\&/)
            @lex_state = :expr_beg

            if scan(/\=/)
              return new_op_asgn('&&')
            end

            return :tANDOP

          elsif scan(/\=/)
            @lex_state = :expr_beg
            return new_op_asgn('&')
          end

          if spcarg?
            #puts "warning: `&' interpreted as argument prefix"
            result = :tAMPER
          elsif beg?
            result = :tAMPER
          else
            #puts "warn_balanced: & argument prefix"
            result = :tAMPER2
          end

          self.set_arg_state
          return result

        elsif scan(/\|/)
          if scan(/\|/)
            @lex_state = :expr_beg
            if scan(/\=/)
              return new_op_asgn('||')
            end

            return :tOROP

          elsif scan(/\=/)
            return new_op_asgn('|')
          end

          self.set_arg_state
          return :tPIPE

        elsif scan(/\%[QqWwixr]/)
          str_type = scanner.matched[1, 1]
          paren = term = scan(/./)

          case term
            when '(' then term = ')'
            when '[' then term = ']'
            when '{' then term = '}'
            when '<' then term = '>'
            else paren = "\0"
          end

          token, func = case str_type
                          when 'Q'
                            [:tSTRING_BEG, STR_DQUOTE]
                          when 'q'
                            [:tSTRING_BEG, STR_SQUOTE]
                          when 'W'
                            skip(/\s*/)
                            [:tWORDS_BEG, STR_DWORD]
                          when 'w', 'i'
                            skip(/\s*/)
                            [:tAWORDS_BEG, STR_SWORD]
                          when 'x'
                            [:tXSTRING_BEG, STR_XQUOTE]
                          when 'r'
                            [:tREGEXP_BEG, STR_REGEXP]
                        end

          self.strterm = new_strterm2(func, term, paren)
          return token

        elsif scan(/\//)
          if beg?
            self.strterm = new_strterm(STR_REGEXP, '/', '/')
            return :tREGEXP_BEG
          elsif scan(/\=/)
            @lex_state = :expr_beg
            return new_op_asgn('/')
          elsif after_operator?
            @lex_state = :expr_arg
          elsif arg?
            if !check(/\s/) && @space_seen
              self.strterm = new_strterm(STR_REGEXP, '/', '/')
              return :tREGEXP_BEG
            end
          else
            @lex_state = :expr_beg
          end

          return :tDIVIDE

        elsif scan(/\%/)
          if scan(/\=/)
            @lex_state = :expr_beg
            return new_op_asgn('%')
          elsif check(/[^\s]/)
            if @lex_state == :expr_beg or (@lex_state == :expr_arg && @space_seen)
              start_word  = scan(/./)
              end_word    = { '(' => ')', '[' => ']', '{' => '}' }[start_word] || start_word
              self.strterm = new_strterm2(STR_DQUOTE, end_word, start_word)
              return :tSTRING_BEG
            end
          end

          self.set_arg_state

          return :tPERCENT

        elsif scan(/\\/)
          if scan(/\r?\n/)
            @space_seen = true
            next
          end

          raise SyntaxError, "backslash must appear before newline :#{@file}:#{@line}"

        elsif scan(/\(/)
          result = scanner.matched
          if beg?
            result = :tLPAREN
          elsif @space_seen && arg?
            result = :tLPAREN_ARG
          else
            result = :tLPAREN2
          end

          @lex_state = :expr_beg
          cond_push 0
          cmdarg_push 0

          return result

        elsif scan(/\)/)
          cond_lexpop
          cmdarg_lexpop
          @lex_state = :expr_end
          return :tRPAREN

        elsif scan(/\[/)
          result = scanner.matched

          if after_operator?
            @lex_state = :expr_arg
            if scan(/\]=/)
              return :tASET
            elsif scan(/\]/)
              return :tAREF
            else
              raise "Unexpected '[' token"
            end
          elsif beg?
            result = :tLBRACK
          elsif arg? && @space_seen
            result =  :tLBRACK
          else
            result = :tLBRACK2
          end

          @lex_state = :expr_beg
          cond_push 0
          cmdarg_push 0
          return result

        elsif scan(/\]/)
          cond_lexpop
          cmdarg_lexpop
          @lex_state = :expr_end
          return :tRBRACK

        elsif scan(/\}/)
          cond_lexpop
          cmdarg_lexpop
          @lex_state = :expr_end

          return :tRCURLY

        elsif scan(/\.\.\./)
          @lex_state = :expr_beg
          return :tDOT3

        elsif scan(/\.\./)
          @lex_state = :expr_beg
          return :tDOT2

        elsif scan(/\./)
          @lex_state = :expr_dot unless @lex_state == :expr_fname
          return :tDOT

        elsif scan(/\:\:/)
          if beg?
            @lex_state = :expr_beg
            return :tCOLON3
          elsif spcarg?
            @lex_state = :expr_beg
            return :tCOLON3
          end

          @lex_state = :expr_dot
          return :tCOLON2

        elsif scan(/\:/)
          if end? || check(/\s/)
            unless check(/\w/)
              @lex_state = :expr_beg
              return :tCOLON
            end

            @lex_state = :expr_fname
            return :tSYMBEG
          end

          if scan(/\'/)
            self.strterm = new_strterm(STR_SSYM, "'", "\0")
          elsif scan(/\"/)
            self.strterm = new_strterm(STR_DSYM, '"', "\0")
          end

          @lex_state = :expr_fname
          return :tSYMBEG

        elsif scan(/\^\=/)
          @lex_state = :expr_beg
          return new_op_asgn('^')

        elsif scan(/\^/)
          self.set_arg_state
          return :tCARET

        elsif check(/\</)
          if scan(/\<\<\=/)
            @lex_state = :expr_beg
            return new_op_asgn('<<')

          elsif scan(/\<\</)
            if after_operator?
              @lex_state = :expr_arg
              return :tLSHFT
            elsif !after_operator? && !end? && (!arg? || @space_seen)
              if token = heredoc_identifier
                return token
              end

              @lex_state = :expr_beg
              return :tLSHFT
            end
            @lex_state = :expr_beg
            return :tLSHFT
          elsif scan(/\<\=\>/)
            if after_operator?
              @lex_state = :expr_arg
            else
              if @lex_state == :expr_class
                cmd_start = true
              end

              @lex_state = :expr_beg
            end

            return :tCMP
          elsif scan(/\<\=/)
            self.set_arg_state
            return :tLEQ

          elsif scan(/\</)
            self.set_arg_state
            return :tLT
          end

        elsif check(/\>/)
          if scan(/\>\>\=/)
            return new_op_asgn('>>')

          elsif scan(/\>\>/)
            self.set_arg_state
            return :tRSHFT

          elsif scan(/\>\=/)
            self.set_arg_state
            return :tGEQ

          elsif scan(/\>/)
            self.set_arg_state
            return :tGT
          end

        elsif scan(/->/)
          # FIXME: # should be :expr_arg, but '(' breaks it...
          @lex_state = :expr_end
          @start_of_lambda = true
          return :tLAMBDA

        elsif scan(/[+-]/)
          matched = scanner.matched
          sign, utype = if matched == '+'
                          [:tPLUS, :tUPLUS]
                        else
                          [:tMINUS, :tUMINUS]
                        end

          if beg?
            @lex_state = :expr_mid
            self.yylval = matched
            return utype
          elsif after_operator?
            @lex_state = :expr_arg
            if scan(/@/)
              self.yylval = matched + '@'
              return :tIDENTIFIER
            end

            self.yylval = matched
            return sign
          end

          if scan(/\=/)
            @lex_state = :expr_beg
            return new_op_asgn(matched)
          end

          if spcarg?
            @lex_state = :expr_mid
            self.yylval = matched
            return utype
          end

          @lex_state = :expr_beg
          self.yylval = matched
          return sign

        elsif scan(/\?/)
          if end?
            @lex_state = :expr_beg
            return :tEH
          end

          if check(/\ |\t|\r|\s/)
            @lex_state = :expr_beg
            return :tEH
          elsif scan(/\\/)
            @lex_state = :expr_end
            self.yylval = self.read_escape
            return :tSTRING
          end

          @lex_state = :expr_end
          self.yylval = scan(/./)
          return :tSTRING

        elsif scan(/\~/)
          self.set_arg_state
          return :tTILDE

        elsif check(/\$/)
          if scan(/\$([1-9]\d*)/)
            @lex_state = :expr_end
            self.yylval = scanner.matched.sub('$', '')
            return :tNTH_REF

          elsif scan(/(\$_)(\w+)/)
            @lex_state = :expr_end
            return :tGVAR

          elsif scan(/\$[\+\'\`\&!@\"~*$?\/\\:;=.,<>_]/)
            @lex_state = :expr_end
            return :tGVAR
          elsif scan(/\$\w+/)
            @lex_state = :expr_end
            return :tGVAR
          else
            raise "Bad gvar name: #{scanner.peek(5).inspect}"
          end

        elsif scan(/\$\w+/)
          @lex_state = :expr_end
          return :tGVAR

        elsif scan(/\@\@\w*/)
          @lex_state = :expr_end
          return :tCVAR

        elsif scan(/\@\w*/)
          @lex_state = :expr_end
          return :tIVAR

        elsif scan(/\,/)
          @lex_state = :expr_beg
          return :tCOMMA

        elsif scan(/\{/)
          if @start_of_lambda
            @start_of_lambda = false
            @lex_state = :expr_beg
            return :tLAMBEG

          elsif arg? or @lex_state == :expr_end
            result = :tLCURLY
          elsif @lex_state == :expr_endarg
            result = :LBRACE_ARG
          else
            result = :tLBRACE
          end

          @lex_state = :expr_beg
          cond_push 0
          cmdarg_push 0
          return result

        elsif scanner.bol? and skip(/\__END__(\n|$)/)
          while true
            if scanner.eos?
              @eof_content = self.yylval
              return false
            end

            scan(/(.*)/)
            scan(/\n/)
          end

        elsif check(/[0-9]/)
          return process_numeric

        elsif scan(/(\w)+[\?\!]?/)
          return process_identifier scanner.matched, cmd_start
        end

        if scanner.eos?
          if @scanner_stack.size == 1 # our main scanner, we cant pop this
            self.yylval = false
            return false
          else # we were probably parsing a heredoc, so pop that parser and continue
            @scanner_stack.pop
            @scanner = @scanner_stack.last
            return yylex
          end
        end

        raise "Unexpected content in parsing stream `#{scanner.peek 5}` :#{@file}:#{@line}"
      end
    end



    def process_numeric
      @lex_state = :expr_end

      if scan(/0b?(0|1|_)+/)
        self.yylval = scanner.matched.to_i(2)
        return :tINTEGER
      elsif scan(/0o?([0-7]|_)+/)
        self.yylval = scanner.matched.to_i(8)
        return :tINTEGER
      elsif scan(/[\d_]+\.[\d_]+\b|[\d_]+(\.[\d_]+)?[eE][-+]?[\d_]+\b/)
        self.yylval = scanner.matched.gsub(/_/, '').to_f
        return :tFLOAT
      elsif scan(/[\d_]+\b/)
        self.yylval = scanner.matched.gsub(/_/, '').to_i
        return :tINTEGER
      elsif scan(/0(x|X)(\d|[a-f]|[A-F]|_)+/)
        self.yylval = scanner.matched.to_i(16)
        return :tINTEGER
      else
        raise "Lexing error on numeric type: `#{scanner.peek 5}`"
      end
    end

    def process_identifier(matched, cmd_start)
      last_state = @lex_state

      if !check(/::/) and scan(/:/)
        @lex_state = :expr_beg
        self.yylval = matched
        return :tLABEL
      end

      if matched == 'defined?'
        if after_operator?
          @lex_state = :expr_end
          return :tIDENTIFIER
        end

        @lex_state = :expr_arg
        return :kDEFINED
      end

      if matched.end_with? '?', '!'
        result = :tIDENTIFIER
      else
        if @lex_state == :expr_fname
          if scan(/\=/)
            result = :tIDENTIFIER
            matched += scanner.matched
          end

        elsif matched =~ /^[A-Z]/
          result = :tCONSTANT
        else
          result = :tIDENTIFIER
        end
      end

      if @lex_state != :expr_dot and kw = Keywords.keyword(matched)
        old_state = @lex_state
        @lex_state = kw.state

        if old_state == :expr_fname
          self.yylval = kw.name
          return kw.id[0]
        end

        if @lex_state == :expr_beg
          cmd_start = true
        end

        if matched == "do"
          if after_operator?
            @lex_state = :expr_end
            return :tIDENTIFIER
          end

          if @start_of_lambda
            @start_of_lambda = false
            @lex_state = :expr_beg
            return :kDO_LAMBDA
          elsif cond?
            @lex_state = :expr_beg
            return :kDO_COND
          elsif cmdarg? && @lex_state != :expr_cmdarg
            @lex_state = :expr_beg
            return :kDO_BLOCK
          elsif @lex_state == :expr_endarg
            return :kDO_BLOCK
          else
            @lex_state = :expr_beg
            return :kDO
          end
        else
          if old_state == :expr_beg or old_state == :expr_value
            self.yylval = matched
            return kw.id[0]
          else
            if kw.id[0] != kw.id[1]
              @lex_state = :expr_beg
            end

            self.yylval = matched
            return kw.id[1]
          end
        end
      end

      if [:expr_beg, :expr_dot, :expr_mid, :expr_arg, :expr_cmdarg].include? @lex_state
        @lex_state = cmd_start ? :expr_cmdarg : :expr_arg
      else
        @lex_state = :expr_end
      end

      if ![:expr_dot, :expr_fname].include?(last_state) and has_local?(matched)
        @lex_state = :expr_end
      end

      return matched =~ /^[A-Z]/ ? :tCONSTANT : :tIDENTIFIER
    end

    def has_local?(local)
      parser.scope.has_local?(local.to_sym)
    end


  end
end