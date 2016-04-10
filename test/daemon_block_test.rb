#!/usr/bin/env ruby

require File.expand_path('../../lib/proxy_daemon/daemon', __FILE__)
require File.expand_path('../../lib/proxy_daemon/worker', __FILE__)

class DaemonBlockTest
  def initialize
    @daemon = ProxyDaemon::Daemon.new('-', proxies: [], urls: ['http://nauchkor.ru/'], workers: 1, tries: 15)
  end
  
  def test
    @daemon.start do |cur, body|
      $stderr.puts "url: #{cur.url}, test: #{foo}"
      $stderr.puts body[0..20]
      true
    end
  end
  
  def foo
    'foo'
  end
end

obj = DaemonBlockTest.new
obj.test