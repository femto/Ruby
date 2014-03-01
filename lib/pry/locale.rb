module Pry # :nodoc:
  class Locale
    LOCALE_NAME_RE = %r[
      (?<language>[[:alpha:]]{2,3})
      (?:_  (?<territory>[[:alpha:]]{2,3}) )?
      (?:\. (?<codeset>[^@]+) )?
      (?:@  (?<modifier>.*) )?
    ]x
    LOCALE_DIR = "/lc/"

    @@legacy_encoding_alias_map = {}.freeze

    def initialize(locale = nil)
      @lang = @territory = @encoding_name = @modifier = nil
      @locale = locale || ENV["PRY_LANG"] || ENV["LC_MESSAGES"] || ENV["LC_ALL"] || ENV["LANG"] || "C"
      if m = LOCALE_NAME_RE.match(@locale)
        @lang, @territory, @encoding_name, @modifier = m[:language], m[:territory], m[:codeset], m[:modifier]

        if @encoding_name
          begin load 'pry/encoding_aliases.rb'; rescue LoadError; end
          if @encoding = @@legacy_encoding_alias_map[@encoding_name]
            warn "%s is obsolete. use %s" % ["#{@lang}_#{@territory}.#{@encoding_name}", "#{@lang}_#{@territory}.#{@encoding.name}"]
          end
          @encoding = Encoding.find(@encoding_name) rescue nil
        end
      end
      @encoding ||= (Encoding.find('locale') rescue Encoding::ASCII_8BIT)
    end

    def load(file, priv=nil)
      found = find(file)
      if found
        return real_load(found, priv)
      else
        raise LoadError, "No such file to load -- #{file}"
      end
    end

    def find(file , paths = $:)
      dir = File.dirname(file)
      dir = "" if dir == "."
      base = File.basename(file)

      if dir.start_with?('/')
        return each_localized_path(dir, base).find{|full_path| File.readable? full_path}
      else
        return search_file(paths, dir, base)
      end
    end

    def search_file(lib_paths, dir, file)
      each_localized_path(dir, file) do |lc_path|
        lib_paths.each do |libpath|
          full_path = File.join(libpath, lc_path)
          return full_path if File.readable?(full_path)
        end
        redo if defined?(Gem) and Gem.try_activate(lc_path)
      end
      nil
    end

    def each_localized_path(dir, file)
      return enum_for(:each_localized_path) unless block_given?
      each_sublocale do |lc|
        yield lc.nil? ? File.join(dir, LOCALE_DIR, file) : File.join(dir, LOCALE_DIR, lc, file)
      end
    end

    def each_sublocale
      if @lang
        if @territory
          if @encoding_name
            yield "#{@lang}_#{@territory}.#{@encoding_name}@#{@modifier}" if @modifier
            yield "#{@lang}_#{@territory}.#{@encoding_name}"
          end
          yield "#{@lang}_#{@territory}@#{@modifier}" if @modifier
          yield "#{@lang}_#{@territory}"
        end
        if @encoding_name
          yield "#{@lang}.#{@encoding_name}@#{@modifier}" if @modifier
          yield "#{@lang}.#{@encoding_name}"
        end
        yield "#{@lang}@#{@modifier}" if @modifier
        yield "#{@lang}"
      end
      yield nil
    end

    attr_reader :lang, :territory, :encoding, :modifieer

    private
    def real_load(path, priv)
      src = MagicFile.open(path){|f| f.read}
      if priv
        eval("self", TOPLEVEL_BINDING).extend(Module.new {eval(src, nil, path)})
      else
        eval(src, TOPLEVEL_BINDING, path)
      end
    end



  end
end