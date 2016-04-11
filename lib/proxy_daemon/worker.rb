require 'colorize'
require 'timeout'
require 'net/http'
require 'openssl'

module ProxyDaemon
  class Worker
    attr_accessor :url
    
    def initialize
      @client = Net::HTTP.Proxy(nil, nil)
      @url = ''
    end
  
    def listen
      begin
        command = ''
        Timeout::timeout(6) {
          command = ($stdin.gets || String.new).strip
          
          if command.empty?
            log "Got empty answer from daemon, exiting...".yellow
            raise Timeout::Error
          end
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
      rescue Errno::EPIPE => e
        log 'Broken pipe with daemon, exiting...'.yellow
        Kernel.exit!
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
      
        res = parse(@page.body)
        
        if !!res == res || res.nil?; answer(res ? 'ok' : 'error')
        elsif res.is_a? Array; answer("set #{res[0]}:#{res[1]}")
        else; answer('error') end
      rescue Timeout::Error, Errno::ETIMEDOUT, Errno::ECONNREFUSED,
      Errno::EINVAL, Errno::ECONNRESET, Errno::ENETUNREACH, SocketError, EOFError,
      TypeError, Net::HTTPExceptions, Net::HTTPBadResponse, OpenSSL::SSL::SSLError => e
        log "proxy".red + " in #{'process'.yellow}: #{e.inspect.red}"
        answer 'proxy'
      rescue Interrupt => e
        log 'Interrupted by user, exiting...'.yellow
        Kernel.exit!
      rescue Exception => e
        log "rescue in #{'process'.yellow}: #{e.inspect},\n#{e.backtrace.reverse.join("\n").red}"
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
      raise NotImplementedError if @block.nil?
      
      @block.call(self, body)
#      instance_exec body, &@block
    end

    def call(&block)
      @block = block if block_given?
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
  
    def log(msg)
      $stderr.puts "[child #{Process.pid}]".magenta + " #{msg}"
    end
  end
end