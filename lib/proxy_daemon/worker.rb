require 'colorize'
require 'timeout'
require 'net/http'
require 'openssl'

module ProxyDaemon
  class Worker
    def initialize
      @client = Net::HTTP.Proxy(nil, nil)
      @url = ''
    end
  
    def listen
      begin
        command = ''
        Timeout::timeout(6) {
          command = ($stdin.gets || String.new).strip
          log "empty!!!" if command.empty?
          raise Timeout::Error if command.empty?
        }
      rescue Timeout::Error
        answer 'timeout'
        Kernel.exit!
      end
  
      command
    end
  
    def answer(command)
      begin
        $stdout.puts "#{command}"
        $stdout.flush
      rescue => e
        log e.inspect.red
      end
    end
  
    def process(url)
      begin
        uri = URI(url)
        Timeout::timeout(15) {
          @client = Net::HTTP.new(uri.host, uri.port)
          @client.use_ssl = (uri.scheme == 'https')
          @client.verify_mode = OpenSSL::SSL::VERIFY_NONE if uri.scheme == 'https'
          #@client.set_debug_output($stderr)

          @client.start { |http|
            req = Net::HTTP::Get.new(uri,
              'Connection' => 'keep-alive',
              'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
              'Upgrade-Insecure-Requests' => '1',
              'User-Agent' => 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/46.0.2490.13 Safari/537.36',
              'Accept-Language' => 'en-US,en;q=0.8,ru;q=0.6'
            )
            @page = http.request(req)
          }
        }
      
        if (!@page.is_a?(Net::HTTPOK) || @page.body.empty?)
          log @page
          raise Net::HTTPBadResponse
        end
      
        answer(parse(@page.body) ? 'ok' : 'error')
      rescue Timeout::Error, Errno::ETIMEDOUT, Errno::ECONNREFUSED,
      Errno::EINVAL, Errno::ECONNRESET, Errno::ENETUNREACH, SocketError, EOFError,
      TypeError, Net::HTTPExceptions, Net::HTTPBadResponse, OpenSSL::SSL::SSLError => e
        log "proxy".red + " in #{'process'.yellow}: #{e.inspect.red}"
        answer 'proxy'
      rescue Exception => e
        log "rescue in #{'process'.yellow}: #{e.inspect}, #{e.backtrace.reverse.join.red}"
        answer 'error'
      end
    end
  
    def changeProxy(proxy)
      if proxy == 'localhost' || proxy.nil? || (proxy = proxy.split(/\s+/)).length < 2
        ENV['http_proxy'] = nil
      else
        ENV['http_proxy'] = "http://#{proxy[0]}:#{proxy[1]}"
      end
    end
  
    def parse(body)
      raise NotImplementedError
    end

    def call
      proxy = nil

      loop do
        begin
          task = listen
          case task
          when /^proxy/
            proxy = task.match(/^proxy\s*(.*)$/)[1]
            changeProxy(proxy)
          when /^url/
            @url = task.match(/^url\s+(.+)$/)[1]
            process(@url)
          when /^exit/
            exit!
          end

          #$stderr.puts "[child #{Process.pid}]".magenta + ' Task: ' + task.to_s.yellow
        rescue => e
          log "rescue in #{'call'.yellow}: #{e.inspect.red}"
          answer 'error'
        end
      end
    end
  
  private
    def log(msg)
      $stderr.puts "[child #{Process.pid}]".magenta + " #{msg}"
    end
  end
end