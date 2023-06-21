require 'time'

class MoesifHelpers
  def initialize(debug)
    @debug = debug
  end

  def log_debug(message)
    return unless @debug

    puts("#{Time.now} [Moesif Middleware] PID #{Process.pid} TID #{Thread.current.object_id} #{message}")
  end
end
