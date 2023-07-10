def is_ip?(value)
  ipv4 = /^(?:(?:\d|[1-9]\d|1\d{2}|2[0-4]\d|25[0-5])\.){3}(?:\d|[1-9]\d|1\d{2}|2[0-4]\d|25[0-5])$/
  ipv6 = /^\s*((([0-9A-Fa-f]{1,4}:){7}([0-9A-Fa-f]{1,4}|:))|(([0-9A-Fa-f]{1,4}:){6}(:[0-9A-Fa-f]{1,4}|((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){5}(((:[0-9A-Fa-f]{1,4}){1,2})|:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})|:))|(([0-9A-Fa-f]{1,4}:){4}(((:[0-9A-Fa-f]{1,4}){1,3})|((:[0-9A-Fa-f]{1,4})?:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){3}(((:[0-9A-Fa-f]{1,4}){1,4})|((:[0-9A-Fa-f]{1,4}){0,2}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){2}(((:[0-9A-Fa-f]{1,4}){1,5})|((:[0-9A-Fa-f]{1,4}){0,3}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(([0-9A-Fa-f]{1,4}:){1}(((:[0-9A-Fa-f]{1,4}){1,6})|((:[0-9A-Fa-f]{1,4}){0,4}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:))|(:(((:[0-9A-Fa-f]{1,4}){1,7})|((:[0-9A-Fa-f]{1,4}){0,5}:((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(\.(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}))|:)))(%.+)?\s*$/
  # We use !! to convert the return value to a boolean
  !!(value =~ ipv4 or value =~ ipv6)
end

def get_client_ip_from_x_forwarded_for(value)
  value = value.encode('utf-8')

  return nil if value.to_s.empty?

  if !value.instance_of?(String)
    puts('Expected a string, got - ' + value.class.to_s)
  else
    # x-forwarded-for may return multiple IP addresses in the format:
    # "client IP, proxy 1 IP, proxy 2 IP"
    # Therefore, the right-most IP address is the IP address of the most recent proxy
    # and the left-most IP address is the IP address of the originating client.
    # source: http://docs.aws.amazon.com/elasticloadbalancing/latest/classic/x-forwarded-headers.html
    # Azure Web App's also adds a port for some reason, so we'll only use the first part (the IP)
    forwardedIps = []

    value.gsub(/\s+/, '').split(',').each do |e|
      if e.include?(':')
        splitted = e.split(':')
        forwardedIps << splitted.first if splitted.length == 2
      end
      forwardedIps << e
    end

    # Sometimes IP addresses in this header can be 'unknown' (http://stackoverflow.com/a/11285650).
    # Therefore taking the left-most IP address that is not unknown
    # A Squid configuration directive can also set the value to "unknown" (http://www.squid-cache.org/Doc/config/forwarded_for/)
    forwardedIps.find { |e| is_ip?(e) }
  end
rescue StandardError
  value.encode('utf-8')
end

def get_client_address(env)
  # Standard headers used by Amazon EC2, Heroku, and others.
  return env['HTTP_X_CLIENT_IP'] if env.key?('HTTP_X_CLIENT_IP') && is_ip?(env['HTTP_X_CLIENT_IP'])

  # Load-balancers (AWS ELB) or proxies.
  if env.key?('HTTP_X_FORWARDED_FOR')
    xForwardedFor = get_client_ip_from_x_forwarded_for(env['HTTP_X_FORWARDED_FOR'])
    return xForwardedFor if is_ip?(xForwardedFor)
  end

  # Cloudflare.
  # @see https://support.cloudflare.com/hc/en-us/articles/200170986-How-does-Cloudflare-handle-HTTP-Request-headers-
  # CF-Connecting-IP - applied to every request to the origin.
  return env['HTTP_CF_CONNECTING_IP'] if env.key?('HTTP_CF_CONNECTING_IP') && is_ip?(env['HTTP_CF_CONNECTING_IP'])

  # Akamai and Cloudflare: True-Client-IP.
  return env['HTTP_TRUE_CLIENT_IP'] if env.key?('HTTP_TRUE_CLIENT_IP') && is_ip?(env['HTTP_TRUE_CLIENT_IP'])

  # Default nginx proxy/fcgi; alternative to x-forwarded-for, used by some proxies.
  return env['HTTP_X_REAL_IP'] if env.key?('HTTP_X_REAL_IP') && is_ip?(env['HTTP_X_REAL_IP'])

  # (Rackspace LB and Riverbed's Stingray)
  # http://www.rackspace.com/knowledge_center/article/controlling-access-to-linux-cloud-sites-based-on-the-client-ip-address
  # https://splash.riverbed.com/docs/DOC-1926
  if env.key?('HTTP_X_CLUSTER_CLIENT_IP') && is_ip?(env['HTTP_X_CLUSTER_CLIENT_IP'])
    return env['HTTP_X_CLUSTER_CLIENT_IP']
  end

  return env['HTTP_X_FORWARDED'] if env.key?('HTTP_X_FORWARDED') && is_ip?(env['HTTP_X_FORWARDED'])

  return env['HTTP_FORWARDED_FOR'] if env.key?('HTTP_FORWARDED_FOR') && is_ip?(env['HTTP_FORWARDED_FOR'])

  return env['HTTP_FORWARDED'] if env.key?('HTTP_FORWARDED') && is_ip?(env['HTTP_FORWARDED'])

  env['REMOTE_ADDR']
rescue StandardError
  env['REMOTE_ADDR']
end
