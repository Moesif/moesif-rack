require 'time'

class MoesifHelpers

    def initialize debug
        @debug = debug
    end

    def log_debug(message)
        if @debug
            puts("#{Time.now.to_s} [Moesif Middleware] PID #{Process.pid} TID #{Thread.current.object_id} #{message}")
        end
    end
end
