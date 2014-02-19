require 'immediate'
require 'bigdecimal'
module Marshal1
  module Type

  end
end


class BasicObject
  def __marshal__(ms, strip_ivars = false)
    out = ms.serialize_extended_object self
    out << "o"
    cls = self.class
    name =  ::Marshal1::Type.module_inspect cls
    out << ms.serialize(name.to_sym)
    out << ms.serialize_instance_variables_suffix(self, true, strip_ivars)
  end
end

class Class
  def __marshal__(ms)
    if Marshal1::Type.singleton_class_object(self)
      raise TypeError, "singleton class can't be dumped"
    elsif name.nil? || name.empty?
      raise TypeError, "can't dump anonymous module #{self}"
    end

    "c#{ms.serialize_integer(name.length)}#{name}"
  end
end

class Module
  def __marshal__(ms)
    raise TypeError, "can't dump anonymous module #{self}" if name.nil? || name.empty?
    "m#{ms.serialize_integer(name.length)}#{name}"
  end
end

class Float
  def __dtoa__
    #s, decimal, sign, digits
    s = ""
    sign = self >= 0 ? 0 : 1
    value = self.abs
    decimal = 0
    digits = 0

    value = BigDecimal.new(self.to_s)
    while value.to_i != value #computing digits after .
      value *= 10
      decimal -= 1
    end

    value = value.to_i
    #now value is an integer
    while value != 0
      if value / 10 * 10 == value #still have 10's power
        value /= 10
        decimal += 1
      end
      break
    end

    #now value
    s = value.to_s
    digits = s.length
    decimal += s.length
    return s, decimal, sign, digits
  end
  def __marshal__(ms)
    if nan?
      str = "nan"
    elsif zero?
      str = (1.0 / self) < 0 ? '-0' : '0'
    elsif infinite?
      str = self < 0 ? "-inf" : "inf"
    else
      s, decimal, sign, digits = __dtoa__

      if decimal < -3 or decimal > digits
        str = s.insert(1, ".") << "e#{decimal - 1}"
      elsif decimal > 0
        str = s[0, decimal]
        digits -= decimal
        str << ".#{s[decimal, digits]}" if digits > 0
      else
        str = "0."
        str << "0" * -decimal if decimal != 0
        str << s[0, digits]
      end
    end

    Marshal1::Type.binary_string("f#{ms.serialize_integer(str.length)}#{str}")
  end
end

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

class Symbol
  def __marshal__(ms)
    if idx = ms.find_symlink(self)
      Type.binary_string(";#{ms.serialize_integer(idx)}")
    else
      ms.add_symlink self
      ms.serialize_symbol(self)
    end
  end
end

class String
  def __marshal__(ms)
    out =  ms.serialize_instance_variables_prefix(self)
    out << ms.serialize_extended_object(self)
    out << ms.serialize_user_class(self, String)
    out << ms.serialize_string(self)
    out << ms.serialize_instance_variables_suffix(self)
    out
  end
end

class Regexp
  IGNORECASE         = 1
  EXTENDED           = 2
  MULTILINE          = 4
  FIXEDENCODING      = 16
  NOENCODING         = 32
  DONT_CAPTURE_GROUP = 128
  CAPTURE_GROUP      = 256

  KCODE_NONE = (1 << 9)
  KCODE_EUC  = (2 << 9)
  KCODE_SJIS = (3 << 9)
  KCODE_UTF8 = (4 << 9)
  KCODE_MASK = KCODE_NONE | KCODE_EUC | KCODE_SJIS | KCODE_UTF8

  OPTION_MASK = IGNORECASE | EXTENDED | MULTILINE | FIXEDENCODING | NOENCODING | DONT_CAPTURE_GROUP | CAPTURE_GROUP
end

class Regexp
  def __marshal__(ms)
    str = self.source
    out =  ms.serialize_instance_variables_prefix(self)
    out << ms.serialize_extended_object(self)
    out << ms.serialize_user_class(self, Regexp)
    out << "/"
    out << ms.serialize_integer(str.length) + str
    out << (options & Regexp::OPTION_MASK).chr
    out << ms.serialize_instance_variables_suffix(self)

    out
  end
end


class Fixnum
  def __marshal__(ms)
    ms.serialize_integer(self, "i")
  end
end

class Bignum
  def __marshal__(ms)
    ms.serialize_bignum(self)
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

    def serialize_encoding?(obj)
      if obj.is_a? String
        enc = obj.encoding
        enc && enc != Encoding::BINARY
      end
    end

    def serialize_encoding(obj)
      case enc = obj.encoding
        when Encoding::US_ASCII
          :E.__marshal__(self) + false.__marshal__(self)
        when Encoding::UTF_8
          :E.__marshal__(self) + true.__marshal__(self)
        else
          :encoding.__marshal__(self) + serialize_string(enc.name)
      end
    end

    def serialize_extended_object(obj)
      str = ''
      if mods = Type.extended_modules(obj)
        mods.each do |mod|
          str << "e#{serialize(mod.name.to_sym)}"
        end
      end
      Type.binary_string(str)
    end

    def serialize_symbol(obj)
      str = obj.to_s
      Type.binary_string(":#{serialize_integer(str.bytesize)}#{str}")
    end

    def serialize_string(str)
      output = Type.binary_string("\"#{serialize_integer(str.bytesize)}")
      output + Type.binary_string(str.dup)
    end

    def serializable_instance_variables(obj, exclude_ivars)
      ivars = obj.instance_variables #todo, make it more private
      ivars -= exclude_ivars if exclude_ivars
      ivars
    end

    def serialize_instance_variables_prefix(obj, exclude_ivars = false)
      ivars = serializable_instance_variables(obj, exclude_ivars)
      Type.binary_string(!ivars.empty? || serialize_encoding?(obj) ? "I" : "")
    end

    def serialize_instance_variables_suffix(obj, force=false,
        strip_ivars=false,
        exclude_ivars=false)
      ivars = serializable_instance_variables(obj, exclude_ivars)

      unless force or !ivars.empty? or serialize_encoding?(obj)
        return Type.binary_string("")
      end

      count = ivars.size

      if serialize_encoding?(obj)
        str = serialize_integer(count + 1)
        str << serialize_encoding(obj)
      else
        str = serialize_integer(count)
      end

      ivars.each do |ivar|
        sym = ivar.to_sym
        val = obj.instance_variable_get(sym) #todo: more safe
        if strip_ivars
          str << serialize(ivar.to_s[1..-1].to_sym)
        else
          str << serialize(sym)
        end
        str << serialize(val)
      end

      Type.binary_string(str)
    end

    def serialize_integer(n, prefix = nil)
      if (n.is_a?(Fixnum)) || ((n >> 31) == 0 or (n >> 31) == -1)
        Type.binary_string(prefix.to_s + serialize_fixnum(n))
      else
        serialize_bignum(n)
      end
    end

    def serialize_fixnum(n)
      if n == 0
        s = n.chr
      elsif n > 0 and n < 123
        s = (n + 5).chr
      elsif n < 0 and n > -124
        s = (256 + (n - 5)).chr
      else
        s = "\0"
        cnt = 0
        4.times do
          s << (n & 0xff).chr
          n >>= 8
          cnt += 1
          break if n == 0 or n == -1
        end
        s[0] = (n < 0 ? 256 - cnt : cnt).chr
      end
      Type.binary_string(s)
    end

    def serialize_bignum(n)
      str = (n < 0 ? 'l-' : 'l+')
      cnt = 0
      num = n.abs

      while num != 0
        str << (num & 0xff).chr
        num >>= 8
        cnt += 1
      end

      if cnt % 2 == 1
        str << "\0"
        cnt += 1
      end

      Type.binary_string(str[0..1] + serialize_fixnum(cnt / 2) + str[2..-1])
    end

    def serialize_user_marshal(obj)
      val = nil
      #Rubinius.privately do
        val = obj.marshal_dump
      #end

      add_object val

      cls = obj.class
      name = Type.module_inspect cls
      Type.binary_string("U#{serialize(name.to_sym)}#{val.__marshal__(self)}")
    end

    def serialize_user_class(obj, cls)
      if obj.class != cls
        Type.binary_string("C#{serialize(obj.class.name.to_sym)}")
      else
        Type.binary_string('')
      end
    end

    def serialize_user_defined(obj)
      if obj.respond_to?(:__custom_marshal__)
        return obj.__custom_marshal__(self)
      end

      str = nil
      #Rubinius.privately do
        str = obj._dump @depth
      #end


      unless str.kind_of?(String)
        raise TypeError, "_dump() must return string"
      end

      out = serialize_instance_variables_prefix(str)
      out << Type.binary_string("u#{serialize(obj.class.name.to_sym)}")
      out << serialize_integer(str.length) + str
      out << serialize_instance_variables_suffix(str)

      out
    end

    def store_unique_object(obj)
      if Symbol === obj
        add_symlink obj
      else
        add_object obj
      end
      obj
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
  module Type
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

    def self.extended_modules(obj)
      singleton_class = (
      class <<obj;
        self;
      end)
      singleton_class.included_modules - obj.class.included_modules
    end

    def self.module_inspect(mod)
      #sc = mod.singleton_class
      #
      #if sc
      #  case sc
      #    when Class, Module
      #      name = "#<Class:#{module_inspect(sc)}>"
      #    else
      #      cls = object_class sc
      #      name = "#<Class:#<#{module_name(cls)}:0x#{sc.object_id.to_s(16)}>>"
      #  end
      #else
      #  name = module_name mod
      #  if !name or name == ""
      #    name = "#<#{object_class(mod)}:0x#{mod.object_id.to_s(16)}>"
      #  end
      #end
      #
      mod.inspect
    end

    def self.singleton_class_object(clazz)
      #todo: determine if clazz is singleton_class
      return false
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

#puts Marshal1.dump(2**30+1)