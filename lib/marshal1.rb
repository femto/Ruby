require 'immediate'

class NilClass
  def __marshal__(ms)
    Marshal1::Type.binary_string("0")
  end
end

class TrueClass
  def __marshal__(ms)
    Marshal1::Type.binary_string("T")
  end
end

class FalseClass
  def __marshal__(ms)
    Marshal1::Type.binary_string("F")
  end
end


module Unmarshalable
  def __marshal__(ms)
    raise TypeError, "marshaling is undefined for class #{self.class}"
  end
end

class Method
  include Unmarshalable
end

class Proc
  include Unmarshalable
end

class IO
  include Unmarshalable
end

class MatchData
  include Unmarshalable
end

module Marshal1
  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  VERSION_STRING = "\x04\x08"

  # Here only for reference
  TYPE_NIL = ?0
  TYPE_TRUE = ?T
  TYPE_FALSE = ?F
  TYPE_FIXNUM = ?i

  TYPE_EXTENDED = ?e
  TYPE_UCLASS = ?C
  TYPE_OBJECT = ?o
  TYPE_DATA = ?d  # no specs
  TYPE_USERDEF = ?u
  TYPE_USRMARSHAL = ?U
  TYPE_FLOAT = ?f
  TYPE_BIGNUM = ?l
  TYPE_STRING = ?"
  TYPE_REGEXP = ?/
  TYPE_ARRAY = ?[
  TYPE_HASH = ?{
  TYPE_HASH_DEF = ?}
  TYPE_STRUCT = ?S
  TYPE_MODULE_OLD = ?M  # no specs
  TYPE_CLASS = ?c
  TYPE_MODULE = ?m

  TYPE_SYMBOL = ?:
  TYPE_SYMLINK = ?;

  TYPE_IVAR = ?I
  TYPE_LINK = ?@

  class State
    def initialize(stream, depth, proc)
      # shared
      @links = Hash.new
      @symlinks = Hash.new
      @symbols = []
      @objects = []

      # dumping
      @depth = depth

      # loading
      if stream
        @stream = stream
      else
        @stream = nil
      end

      if stream
        @consumed = 2
      else
        @consumed = 0
      end

      @modules = nil
      @has_ivar = []
      @proc = proc
      @call = true
    end

    def add_object(obj)
      return if obj.kind_of?(ImmediateValue)
      sz = @links.size
      @objects[sz] = obj
      @links[obj.__id__] = sz
    end

    def add_symlink(obj)
      sz = @symlinks.size
      @symbols[sz] = obj
      @symlinks[obj.__id__] = sz
    end

    def construct(ivar_index = nil, call_proc = true)
      type = consume_byte()
      obj = case type
              when 48   # ?0
                nil
              when 84   # ?T
                true
              when 70   # ?F
                false
              when 99   # ?c
                construct_class
              when 109  # ?m
                construct_module
              when 77   # ?M
                construct_old_module
              when 105  # ?i
                construct_integer
              when 108  # ?l
                construct_bignum
              when 102  # ?f
                construct_float
              when 58   # ?:
                construct_symbol
              when 34   # ?"
                construct_string
              when 47   # ?/
                construct_regexp
              when 91   # ?[
                construct_array
              when 123  # ?{
                construct_hash
              when 125  # ?}
                construct_hash_def
              when 83   # ?S
                construct_struct
              when 111  # ?o
                construct_object
              when 117  # ?u
                construct_user_defined ivar_index
              when 85   # ?U
                construct_user_marshal
              when 100  # ?d
                construct_data
              when 64   # ?@
                num = construct_integer
                obj = @objects[num]

                raise ArgumentError, "dump format error (unlinked)" unless obj

                return obj
              when 59   # ?;
                num = construct_integer
                sym = @symbols[num]

                raise ArgumentError, "bad symbol" unless sym

                return sym
              when 101  # ?e
                @modules ||= []

                name = get_symbol
                @modules << const_lookup(name, Module)

                obj = construct nil, false

                extend_object obj

                obj
              when 67   # ?C
                name = get_symbol
                @user_class = name

                construct nil, false

              when 73   # ?I
                ivar_index = @has_ivar.length
                @has_ivar.push true

                obj = construct ivar_index, false

                set_instance_variables obj if @has_ivar.pop

                obj
              else
                raise ArgumentError, "load error, unknown type #{type}"
            end

      call obj if @proc and call_proc

      @stream.tainted? && !obj.frozen? ? obj.taint : obj
    end

    def construct_integer
      c = consume_byte()

      # The format appears to be a simple integer compression format
      #
      # The 0-123 cases are easy, and use one byte
      # We've read c as unsigned char in a way, but we need to honor
      # the sign bit. We do that by simply comparing with the +128 values
      return 0 if c == 0
      return c - 5 if 4 < c and c < 128

      # negative, but checked known it's instead in 2's complement
      return c - 251 if 252 > c and c > 127

      # otherwise c (now in the 1 to 4 range) indicates how many
      # bytes to read to construct the value.
      #
      # Because we're operating on a small number of possible values,
      # it's cleaner to just unroll the calculate of each

      case c
        when 1
          consume_byte
        when 2
          consume_byte | (consume_byte << 8)
        when 3
          consume_byte | (consume_byte << 8) | (consume_byte << 16)
        when 4
          consume_byte | (consume_byte << 8) | (consume_byte << 16) |
              (consume_byte << 24)

        when 255 # -1
          consume_byte - 256
        when 254 # -2
          (consume_byte | (consume_byte << 8)) - 65536
        when 253 # -3
          (consume_byte |
              (consume_byte << 8) |
              (consume_byte << 16)) - 16777216 # 2 ** 24
        when 252 # -4
          (consume_byte |
              (consume_byte << 8) |
              (consume_byte << 16) |
              (consume_byte << 24)) - 4294967296
        else
          raise "Invalid integer size: #{c}"
      end
    end


    #######serialize part###########
    def find_link(obj)
      @links[obj.__id__]
    end

    def find_symlink(obj)
      @symlinks[obj.__id__]
    end

    def serialize(obj)
      raise ArgumentError, "exceed depth limit" if @depth == 0

      # How much depth we have left.
      @depth -= 1;

      if link = find_link(obj)
        str = Type.binary_string("@#{serialize_integer(link)}")
      else
        add_object obj

        # ORDER MATTERS.
        if obj.respond_to?(:marshal_dump, true)
          str = serialize_user_marshal obj
        elsif obj.respond_to?(:_dump,true)
          str = serialize_user_defined obj
        else
          str = obj.__marshal__ self
        end
      end

      @depth += 1

      Type.infect(str, obj)
    end

  end
  class IOState < State
    def consume(bytes)
      @stream.read(bytes)
    end

    def consume_byte
      b = @stream.getbyte
      raise EOFError unless b
      b
    end
  end

  class StringState < State
    def initialize(stream, depth, prc)
      super stream, depth, prc

      if @stream
        @byte_array = stream.bytes
      end

    end

    def consume(bytes)
      #raise ArgumentError, "marshal data too short" if @consumed > @stream.bytesize
      data = @stream.byteslice @consumed, bytes
      @consumed += bytes
      data
    end

    def consume_byte
      #raise ArgumentError, "marshal data too short" if @consumed >= @stream.bytesize
      data = @byte_array[@consumed]
      @consumed += 1
      return data
    end
  end
  class Type
    def self.coerce_to(obj, cls, meth)
      return obj if obj.kind_of?(cls)
      execute_coerce_to(obj, cls, meth)
    end

    def self.execute_coerce_to(obj, cls, meth)
      begin
        ret = obj.__send__(meth)
      rescue Exception => orig
        raise TypeError,
              "Coercion error: #{obj.inspect}.#{meth} => #{cls} failed",
              orig
      end

      return ret if ret.kind_of?(cls)

      msg = "Coercion error: obj.#{meth} did NOT return a #{cls} (was #{ret.class})"
      raise TypeError, msg
    end

    def self.binary_string(string)
      string.force_encoding Encoding::BINARY
    end

    def self.infect(host, source)
      host.taint if source.tainted?
      host
    end

  end

  class << self

    def dump(obj, an_io=nil, limit=nil)
      unless limit
        if an_io.kind_of?(Fixnum)
          limit = an_io
          an_io = nil
        else
          limit = -1
        end
      end

      depth = Type.coerce_to(limit, Fixnum, :to_int)
      ms = State.new nil, depth, nil

      if an_io
        if !an_io.respond_to?(:write)
          raise TypeError, "output must respond to write"
        end
        if an_io.respond_to?(:binmode)
          an_io.binmode
        end
      end

      str = Type.binary_string(VERSION_STRING) + ms.serialize(obj)

      if an_io
        an_io.write(str)
        return an_io
      end

      return str
    end

    def load(obj, prc = nil)
      if obj.respond_to?(:to_str)
        data = obj.to_s

        major = data.getbyte 0
        minor = data.getbyte 1

        ms = StringState.new data, nil, prc

      elsif obj.respond_to?(:read) and
          obj.respond_to?(:getc)
        ms = IOState.new obj, nil, prc

        major = ms.consume_byte
        minor = ms.consume_byte
      else
        raise TypeError, "instance of IO needed"
      end

      if major != MAJOR_VERSION or minor > MINOR_VERSION
        raise TypeError, "incompatible marshal file format (can't be read)\n\tformat version #{MAJOR_VERSION}.#{MINOR_VERSION} required; #{major.inspect}.#{minor.inspect} given"
      end

      ms.construct
    end
    alias_method :restore, :load
  end
end