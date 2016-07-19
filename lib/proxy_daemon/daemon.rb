require 'thread'
require 'timeout'
require 'json'
require 'colorize'

module ProxyDaemon
  class Daemon
    attr_accessor :list

    def initialize(script_or_parser, options = nil)
      if script_or_parser.is_a? String then @script = script_or_parser
      else
        @script = '-'
        
        if script_or_parser.is_a? Hash then options = script_or_parser
        else @parser = script_or_parser end
      end
      
      @proxies = ((options[:proxies].map { |proxy| proxy.gsub /\s+/, ' ' }) || [])#.shuffle
      @urls = options[:urls] || []
      @worker_processes = (options[:worker_processes] || 10)
      @tries = options[:tries] || 4

      @threads = []
      @list = {}
      @semaphore = Mutex.new
    end

    def command(cmd, pipe, params = {})
      command = {command: cmd}.merge(params)
      
      Thread.current[:command] = cmd
      pipe.puts(command.to_json)
    end

    def listen(pipe, try = 0)
      packet = JSON.parse((pipe.gets || '').strip)
      raise "Empty answer from worker process" if packet.empty?
      answer = packet['answer']
      raise "Process: '#{answer}'" if answer == 'timeout' || answer == 'error'
      
      if answer == 'proxy'
        raise "Broken url: #{Thread.current[:url]}" if try > @tries

        proxy = getProxy
        log "Answer: #{answer}, data: #{packet['data']}".yellow, pipe
        log "Choosing new proxy: #{(proxy || 'nil').yellow}", pipe
        command :proxy, pipe, proxy: proxy
#        command :url, pipe, url: Thread.current[:url]
        listen pipe, try+1
      elsif answer == 'ok'
        @semaphore.synchronize { @list.merge! packet['data'] } if packet.key? 'data'
        log "Process: #{Thread.current[:url].cyan}: '#{answer.green}', data: #{packet['data'].to_json}", pipe
      else
        log "Answer: #{answer}, data: #{packet['data'].to_json}".green, pipe
      end
    end

    def worker
      IO.popen("#{@script}", 'r+') { |p|
        if (@script == '-' && p.nil?) # child process
          if @block.nil? && @parser.nil?
            $stderr.syswrite "[#{Process.pid}]".magenta + ' The parser is undefined and block wasn\'t given for parsing the content'.red + "\n"
            $stderr.flush

            Kernel.exit!
          end
          
          if @parser
            worker = ProxyDaemon::Worker.new(@parser, @parse_method)
            worker.call
          elsif @block
            worker = ProxyDaemon::Worker.new
            worker.call(&@block)
          end
        else
          p.sync = true
          proxy = getProxy
          log "Starting loop with new proxy: ".green + "#{(proxy || 'nil').yellow}", p
          command :proxy, p, proxy: proxy

          begin
            loop do
              sleep(0.1)
              url = getUrl

              if url.nil?
                finished "Links are finished! exitting...".green, p
                command :exit, p
                break
              else
                log 'Urls count: ' + "#{@urls.length}".green + ", #{url.green}"
                Thread.current[:url] = url
                command :url, p, url: url
                listen p
              end
            end

            log "Finishing loop".green, p
          rescue Exception => e
            @semaphore.synchronize {
              log "Exception in main:".red + " '#{Thread.current[:url]}'".yellow + " #{e.message.red}".red + "\n#{e.backtrace.join("\n").red}\n", p
              command :exit, p
              #puts e.backtrace
            }
          end
        end
      }

      if @urls.length > 0
        # @threads << Thread.new(&(->{worker}))
        # @threads.last.join
        worker
      end
    end

    def start(options = nil, &block)
      @block = block if block_given?
      @parse_method = options[:parse] if options && options.key?(:parse)
      worker_processes = [@worker_processes, @urls.count].min
      
      begin
        puts "[main] Starting " + "#{worker_processes}".yellow + " workers:"
        worker_processes.times { |i| @threads << Thread.new(&(->{worker})) }
        @threads.each { |t| t.join }
      rescue Interrupt => e
        puts "[main] Interrupted by user".yellow
      end
    end

    def add_urls(urls)
      @semaphore.synchronize { @urls |= [*urls] }
    end

  private
    def getProxy
      proxy = String.new
      @semaphore.synchronize {
        proxy = @proxies.first
        @proxies.rotate!
      }

      proxy
    end

    def getUrl
      url = String.new
      @semaphore.synchronize { url = @urls.shift }

      url
    end

    def finished(msg, pipe = 0)
      unless @finished
        @finished = true
        @semaphore.synchronize { log msg, pipe }
      end
    end

    def log(msg, pipe = nil)
      unless pipe.nil? then $stdout.syswrite "[#{pipe.pid}]".blue + " #{msg}\n"
      else $stdout.syswrite "#{msg}\n" end
      $stdout.flush
    end
  end
end
