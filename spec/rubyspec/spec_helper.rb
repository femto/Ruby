$: << File.join(File.expand_path(__FILE__),"..","lib")

# Creates a temporary directory in the current working directory
# for temporary files created while running the specs. All specs
# should clean up any temporary files created so that the temp
# directory is empty when the process exits.

SPEC_TEMP_DIR = "#{File.expand_path(Dir.pwd)}/rubyspec_temp"

SPEC_TEMP_UNIQUIFIER = "0"

SPEC_TMEM_DIR_PID = Process.pid

at_exit do
  begin
    if SPEC_TMEM_DIR_PID == Process.pid
      Dir.delete SPEC_TEMP_DIR if File.directory? SPEC_TEMP_DIR
    end
  rescue SystemCallError
    STDERR.puts <<-EOM

-----------------------------------------------------
The rubyspec temp directory is not empty. Ensure that
all specs are cleaning up temporary files:
  #{SPEC_TEMP_DIR}
-----------------------------------------------------

    EOM
  rescue Object => e
    STDERR.puts "failed to remove spec temp directory"
    STDERR.puts e.message
  end
end

class Object
  def tmp(name, uniquify=true)
    Dir.mkdir SPEC_TEMP_DIR unless File.exists? SPEC_TEMP_DIR

    if uniquify and !name.empty?
      slash = name.rindex "/"
      index = slash ? slash + 1 : 0
      name.insert index, "#{SPEC_TEMP_UNIQUIFIER.succ!}-"
    end

    File.join SPEC_TEMP_DIR, name
  end

  # Recursively removes all files and directories in +path+
  # if +path+ is a directory. Removes the file if +path+ is
  # a file.
  def rm_r(*paths)
    paths.each do |path|
      path = File.expand_path path

      prefix = SPEC_TEMP_DIR
      unless path[0, prefix.size] == prefix
        raise ArgumentError, "#{path} is not prefixed by #{prefix}"
      end

      # File.symlink? needs to be checked first as
      # File.exists? returns false for dangling symlinks
      if File.symlink? path
        File.unlink path
      elsif File.directory? path
        Dir.entries(path).each { |x| rm_r "#{path}/#{x}" unless x =~ /^\.\.?$/ }
        Dir.rmdir path
      elsif File.exists? path
        File.delete path
      end
    end
  end
end


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