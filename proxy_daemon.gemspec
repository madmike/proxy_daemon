# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'proxy_daemon/version'

Gem::Specification.new do |spec|
  spec.name          = 'proxy_daemon'
  spec.version       = ProxyDaemon::VERSION
  spec.authors       = ['Michail Volkov']
  spec.email         = ['xbiznet@gmail.com']

  spec.summary       = %q{Simple daemon for grabbing sites via proxy servers.}
  spec.description   = %q{Daemon and base worker for grabbing site pages via list of proxies in parallel.}
  spec.homepage      = 'http://rubygems.org/gems/proxy-daemon'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'bin'
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.11'
  spec.add_development_dependency 'rake', '~> 10.0'
  
  spec.add_runtime_dependency 'colorize'
  spec.add_runtime_dependency 'openssl'
end
