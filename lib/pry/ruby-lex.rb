require "e2mmap"
require "pry/slex"
#require "pry/ruby-token"

class RubyLex
  attr_accessor :exception_on_syntax_error

  extend Exception2MessageMapper
  def_exception(:AlreadyDefinedToken, "Already defined token(%s)")
  def_exception(:TkReading2TokenNoKey, "key nothing(key='%s')")
  def_exception(:TkSymbol2TokenNoKey, "key nothing(key='%s')")
  def_exception(:TkReading2TokenDuplicateError,
                "key duplicate(token_n='%s', key='%s')")
  def_exception(:SyntaxError, "%s")

  def_exception(:TerminateLineInput, "Terminate Line Input")


  EXPR_BEG = :EXPR_BEG
  EXPR_MID = :EXPR_MID
  EXPR_END = :EXPR_END
  EXPR_ARG = :EXPR_ARG
  EXPR_FNAME = :EXPR_FNAME
  EXPR_DOT = :EXPR_DOT
  EXPR_CLASS = :EXPR_CLASS

  class << self
    attr_accessor :debug_level
    def debug?
      @debug_level > 0
    end
  end
  @debug_level = 0

  def initialize
    lex_init
    set_input(STDIN)

    @seek = 0
    @exp_line_no = @line_no = 1
    @base_char_no = 0
    @char_no = 0
    @rests = []
    @readed = []
    @here_readed = []

    @indent = 0
    @indent_stack = []
    @lex_state = EXPR_BEG
    @space_seen = false
    @here_header = false
    @post_symbeg = false

    @continue = false
    @line = ""

    @skip_space = false
    @readed_auto_clean_up = false
    @exception_on_syntax_error = true

    @prompt = nil
  end

  def lex_init()
    @OP = Pry::SLex.new
    @OP.def_rules("\0", "\004", "\032") do |op, io|
      Token(TkEND_OF_SCRIPT)
    end

    @OP.def_rules(" ", "\t", "\f", "\r", "\13") do |op, io|
      @space_seen = true
      while getc =~ /[ \t\f\r\13]/; end
      ungetc
      Token(TkSPACE)
    end

    @OP.def_rule("#") do |op, io|
      identify_comment
    end

    @OP.def_rule("=begin",
                 proc{|op, io| @prev_char_no == 0 && peek(0) =~ /\s/}) do  |op, io|
      @ltype = "="
      until getc == "\n"; end
      until peek_equal?("=end") && peek(4) =~ /\s/
        until getc == "\n"; end
      end
      gets
      @ltype = nil
      Token(TkRD_COMMENT)
    end

    @OP.def_rule("\n") do |op, io|
      print "\\n\n" if RubyLex.debug?
      case @lex_state
        when EXPR_BEG, EXPR_FNAME, EXPR_DOT
          @continue = true
        else
          @continue = false
          @lex_state = EXPR_BEG
          until (@indent_stack.empty? ||
              [TkLPAREN, TkLBRACK, TkLBRACE,
               TkfLPAREN, TkfLBRACK, TkfLBRACE].include?(@indent_stack.last))
            @indent_stack.pop
          end
      end
      @here_header = false
      @here_readed = []
      Token(TkNL)
    end

    @OP.def_rules("*", "**",
                  "=", "==", "===",
                  "=~", "<=>",
                  "<", "<=",
                  ">", ">=", ">>",
                  "!", "!=", "!~") do
    |op, io|
      case @lex_state
        when EXPR_FNAME, EXPR_DOT
          @lex_state = EXPR_ARG
        else
          @lex_state = EXPR_BEG
      end
      Token(op)
    end

    @OP.def_rules("<<") do
    |op, io|
      tk = nil
      if @lex_state != EXPR_END && @lex_state != EXPR_CLASS &&
          (@lex_state != EXPR_ARG || @space_seen)
        c = peek(0)
        if /\S/ =~ c && (/["'`]/ =~ c || /\w/ =~ c || c == "-")
          tk = identify_here_document
        end
      end
      unless tk
        tk = Token(op)
        case @lex_state
          when EXPR_FNAME, EXPR_DOT
            @lex_state = EXPR_ARG
          else
            @lex_state = EXPR_BEG
        end
      end
      tk
    end

    @OP.def_rules("'", '"') do
    |op, io|
      identify_string(op)
    end

    @OP.def_rules("`") do
    |op, io|
      if @lex_state == EXPR_FNAME
        @lex_state = EXPR_END
        Token(op)
      else
        identify_string(op)
      end
    end

    @OP.def_rules('?') do
    |op, io|
      if @lex_state == EXPR_END
        @lex_state = EXPR_BEG
        Token(TkQUESTION)
      else
        ch = getc
        if @lex_state == EXPR_ARG && ch =~ /\s/
          ungetc
          @lex_state = EXPR_BEG;
          Token(TkQUESTION)
        else
          if (ch == '\\')
            read_escape
          end
          @lex_state = EXPR_END
          Token(TkINTEGER)
        end
      end
    end

    @OP.def_rules("&", "&&", "|", "||") do
    |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end

    @OP.def_rules("+=", "-=", "*=", "**=",
                  "&=", "|=", "^=", "<<=", ">>=", "||=", "&&=") do
    |op, io|
      @lex_state = EXPR_BEG
      op =~ /^(.*)=$/
      Token(TkOPASGN, $1)
    end

    @OP.def_rule("+@", proc{|op, io| @lex_state == EXPR_FNAME}) do
    |op, io|
      @lex_state = EXPR_ARG
      Token(op)
    end

    @OP.def_rule("-@", proc{|op, io| @lex_state == EXPR_FNAME}) do
    |op, io|
      @lex_state = EXPR_ARG
      Token(op)
    end

    @OP.def_rules("+", "-") do
    |op, io|
      catch(:RET) do
        if @lex_state == EXPR_ARG
          if @space_seen and peek(0) =~ /[0-9]/
            throw :RET, identify_number
          else
            @lex_state = EXPR_BEG
          end
        elsif @lex_state != EXPR_END and peek(0) =~ /[0-9]/
          throw :RET, identify_number
        else
          @lex_state = EXPR_BEG
        end
        Token(op)
      end
    end

    @OP.def_rule(".") do
    |op, io|
      @lex_state = EXPR_BEG
      if peek(0) =~ /[0-9]/
        ungetc
        identify_number
      else
        # for "obj.if" etc.
        @lex_state = EXPR_DOT
        Token(TkDOT)
      end
    end

    @OP.def_rules("..", "...") do
    |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end

    lex_int2
  end

  def lex_int2
    @OP.def_rules("]", "}", ")") do
    |op, io|
      @lex_state = EXPR_END
      @indent -= 1
      @indent_stack.pop
      Token(op)
    end

    @OP.def_rule(":") do
    |op, io|
      if @lex_state == EXPR_END || peek(0) =~ /\s/
        @lex_state = EXPR_BEG
        Token(TkCOLON)
      else
        @lex_state = EXPR_FNAME
        Token(TkSYMBEG)
      end
    end

    @OP.def_rule("::") do
    |op, io|

      if @lex_state == EXPR_BEG or @lex_state == EXPR_ARG && @space_seen
        @lex_state = EXPR_BEG
        Token(TkCOLON3)
      else
        @lex_state = EXPR_DOT
        Token(TkCOLON2)
      end
    end

    @OP.def_rule("/") do
    |op, io|
      if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
        identify_string(op)
      elsif peek(0) == '='
        getc
        @lex_state = EXPR_BEG
        Token(TkOPASGN, "/") #/)
      elsif @lex_state == EXPR_ARG and @space_seen and peek(0) !~ /\s/
        identify_string(op)
      else
        @lex_state = EXPR_BEG
        Token("/") #/)
      end
    end

    @OP.def_rules("^") do
    |op, io|
      @lex_state = EXPR_BEG
      Token("^")
    end

    #       @OP.def_rules("^=") do
    # 	@lex_state = EXPR_BEG
    # 	Token(OP_ASGN, :^)
    #       end

    @OP.def_rules(",") do
    |op, io|
      @lex_state = EXPR_BEG
      Token(op)
    end

    @OP.def_rules(";") do
    |op, io|
      @lex_state = EXPR_BEG
      until (@indent_stack.empty? ||
          [TkLPAREN, TkLBRACK, TkLBRACE,
           TkfLPAREN, TkfLBRACK, TkfLBRACE].include?(@indent_stack.last))
        @indent_stack.pop
      end
      Token(op)
    end

    @OP.def_rule("~") do
    |op, io|
      @lex_state = EXPR_BEG
      Token("~")
    end

    @OP.def_rule("~@", proc{|op, io| @lex_state == EXPR_FNAME}) do
    |op, io|
      @lex_state = EXPR_BEG
      Token("~")
    end

    @OP.def_rule("(") do
    |op, io|
      @indent += 1
      if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
        @lex_state = EXPR_BEG
        tk_c = TkfLPAREN
      else
        @lex_state = EXPR_BEG
        tk_c = TkLPAREN
      end
      @indent_stack.push tk_c
      Token(tk_c)
    end

    @OP.def_rule("[]", proc{|op, io| @lex_state == EXPR_FNAME}) do
    |op, io|
      @lex_state = EXPR_ARG
      Token("[]")
    end

    @OP.def_rule("[]=", proc{|op, io| @lex_state == EXPR_FNAME}) do
    |op, io|
      @lex_state = EXPR_ARG
      Token("[]=")
    end

    @OP.def_rule("[") do
    |op, io|
      @indent += 1
      if @lex_state == EXPR_FNAME
        tk_c = TkfLBRACK
      else
        if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
          tk_c = TkLBRACK
        elsif @lex_state == EXPR_ARG && @space_seen
          tk_c = TkLBRACK
        else
          tk_c = TkfLBRACK
        end
        @lex_state = EXPR_BEG
      end
      @indent_stack.push tk_c
      Token(tk_c)
    end

    @OP.def_rule("{") do
    |op, io|
      @indent += 1
      if @lex_state != EXPR_END && @lex_state != EXPR_ARG
        tk_c = TkLBRACE
      else
        tk_c = TkfLBRACE
      end
      @lex_state = EXPR_BEG
      @indent_stack.push tk_c
      Token(tk_c)
    end

    @OP.def_rule('\\') do
    |op, io|
      if getc == "\n"
        @space_seen = true
        @continue = true
        Token(TkSPACE)
      else
        read_escape
        Token("\\")
      end
    end

    @OP.def_rule('%') do
    |op, io|
      if @lex_state == EXPR_BEG || @lex_state == EXPR_MID
        identify_quotation
      elsif peek(0) == '='
        getc
        Token(TkOPASGN, :%)
      elsif @lex_state == EXPR_ARG and @space_seen and peek(0) !~ /\s/
        identify_quotation
      else
        @lex_state = EXPR_BEG
        Token("%") #))
      end
    end

    @OP.def_rule('$') do
    |op, io|
      identify_gvar
    end

    @OP.def_rule('@') do
    |op, io|
      if peek(0) =~ /[\w@]/
        ungetc
        identify_identifier
      else
        Token("@")
      end
    end

    #       @OP.def_rule("def", proc{|op, io| /\s/ =~ io.peek(0)}) do
    # 	|op, io|
    # 	@indent += 1
    # 	@lex_state = EXPR_FNAME
    # #	@lex_state = EXPR_END
    # #	until @rests[0] == "\n" or @rests[0] == ";"
    # #	  rests.shift
    # #	end
    #       end

    @OP.def_rule("") do
    |op, io|
      printf "MATCH: start %s: %s\n", op, io.inspect if RubyLex.debug?
      if peek(0) =~ /[0-9]/
        t = identify_number
      elsif peek(0) =~ /[^\x00-\/:-@\[-^`{-\x7F]/
        t = identify_identifier
      end
      printf "MATCH: end %s: %s\n", op, io.inspect if RubyLex.debug?
      t
    end

    p @OP if RubyLex.debug?
  end



  def token
    @prev_seek = @seek
    @prev_line_no = @line_no
    @prev_char_no = @char_no
    begin
      begin
        tk = @OP.match(self)
        @space_seen = tk.kind_of?(TkSPACE)
        @lex_state = EXPR_END if @post_symbeg && tk.kind_of?(TkOp)
        @post_symbeg = tk.kind_of?(TkSYMBEG)
      rescue SyntaxError
        raise if @exception_on_syntax_error
        tk = TkError.new(@seek, @line_no, @char_no)
      end
    end while @skip_space and tk.kind_of?(TkSPACE)
    if @readed_auto_clean_up
      get_readed
    end
    tk
  end

  def buf_input
    prompt
    line = @input.call
    return nil unless line
    @rests.concat line.chars.to_a
    true
  end
  private :buf_input

  def getc
    while @rests.empty?
      @rests.push nil unless buf_input
    end
    c = @rests.shift
    if @here_header
      @here_readed.push c
    else
      @readed.push c
    end
    @seek += 1
    if c == "\n"
      @line_no += 1
      @char_no = 0
    else
      @char_no += 1
    end
    c
  end

  def set_prompt(p = nil, &block)
    p = block if block_given?
    if p.respond_to?(:call)
      @prompt = p
    else
      @prompt = Proc.new{print p}
    end
  end

  def set_input(io, p = nil, &block)
    @io = io
    if p.respond_to?(:call)
      @input = p
    elsif block_given?
      @input = block
    else
      @input = Proc.new{@io.gets}
    end
  end

  def prompt
    if @prompt
      @prompt.call(@ltype, @indent, @continue, @line_no)
    end
  end

  def initialize_input
    @ltype = nil
    @quoted = nil
    @indent = 0
    @indent_stack = []
    @lex_state = EXPR_BEG
    @space_seen = false
    @here_header = false

    @continue = false
    @post_symbeg = false

    prompt

    @line = ""
    @exp_line_no = @line_no
  end

  def lex
    until (((tk = token).kind_of?(TkNL) || tk.kind_of?(TkEND_OF_SCRIPT)) &&
        !@continue or  tk.nil?)
    end
    line = get_readed

    if line == "" and tk.kind_of?(TkEND_OF_SCRIPT) || tk.nil?
      nil
    else
      line
    end
  end

  def ungetc(c = nil)
    if @here_readed.empty?
      c2 = @readed.pop
    else
      c2 = @here_readed.pop
    end
    c = c2 unless c
    @rests.unshift c #c =
    @seek -= 1
    if c == "\n"
      @line_no -= 1
      if idx = @readed.rindex("\n")
        @char_no = idx + 1
      else
        @char_no = @base_char_no + @readed.size
      end
    else
      @char_no -= 1
    end
  end

  def each_top_level_statement
    initialize_input
    catch(:TERM_INPUT) do
      loop do
        begin
          @continue = false
          prompt
          unless l = lex
            throw :TERM_INPUT if @line == ''
          else
            @line.concat l
            if @ltype or @continue or @indent > 0
              next
            end
          end
          if @line != "\n"
            @line.force_encoding(@io.encoding)
            yield @line, @exp_line_no
          end
          break unless l
          @line = ''
          @exp_line_no = @line_no

          @indent = 0
          @indent_stack = []
          prompt
        rescue TerminateLineInput
          initialize_input
          prompt
          get_readed
        end
      end
    end
  end
end