class NullRedis

  def offline_notice
    return if @offline_notice

    @offline_notice = true
    puts 'WARNING! Redis is offline. Run `brew install redis` and `brew services start redis`.'.colorize(:red)
  end

  %i[get set del unlink].each do |method|
    define_method(method) do |*_args|
      offline_notice
    end
  end

  def keys(*_args)
    []
  end

end
