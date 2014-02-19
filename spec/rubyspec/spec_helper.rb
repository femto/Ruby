$: << File.join(File.expand_path(__FILE__),"..","lib")

class Object
  def ruby_version_is(*args)
    yield
  end
  def with_feature(*args)
    yield
  end
end