Gem::Specification.new do |s|
  s.name = 'moesif_rack'
  s.version = '1.4.5'
  s.summary = 'moesif_rack'
  s.description = 'Rack/Rails middleware to log API calls to Moesif API analytics and monitoring'
  s.authors = ['Moesif, Inc', 'Xing Wang']
  s.email = 'xing@moesif.com'
  s.homepage = 'https://moesif.com'
  s.license = 'Apache-2.0'
  s.add_development_dependency('test-unit', '~> 3.1', '>= 3.1.5')
  s.add_dependency('moesif_api', '~> 1.2', '>= 1.2.12')
  s.required_ruby_version = '~> 2.0'
  s.files = Dir['{bin,lib,moesif_capture_outgoing,man,test,spec}/**/*', 'README*', 'LICENSE*']
  s.require_paths = ['lib']
end
