$: << File.join(File.expand_path(__FILE__),"..","lib")

class Object
  def ruby_version_is(*args)
    yield
  end
  def with_feature(*args)
    yield
  end
end

class Object
  def nan_value
    0/0.0
  end

  def infinity_value
    1/0.0
  end

  def bignum_value(plus=0)
    0x8000_0000_0000_0000 + plus
  end
end

class Object
  # Helper to handle String encodings. The +str+ and +encoding+ parameters
  # must be Strings and an ArgumentError will be raised if not. This ensures
  # that the encode() helper can be used regardless of whether Encoding exits.
  # The helper is a no-op (i.e. passes through +str+ unmodified) if the
  # :encoding feature is not enabled (see with_feature guard).  If the
  # :encoding feature is enabled, +str+.force_encoding(+encoding+) is called.
  def encode(str, encoding)
    unless str.is_a? String and encoding.is_a? String
      raise ArgumentError, "encoding name must be a String"
    end

    #if FeatureGuard.enabled? :encoding
      str.force_encoding encoding
    #end

    str
  end
end