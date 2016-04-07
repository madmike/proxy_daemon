require 'thread'
require 'timeout'
require 'json'
require 'colorize'

module ProxyDaemon
  class Daemon
    def initialize(script, options)
      @script = script
      @proxies = ((options[:proxies].map { |proxy| proxy.gsub /\s+/, ' ' }) || []).shuffle
      @urls = options[:urls] || []
      @workers = options[:workers] || 10
      @tries = options[:tries] || 4
    
      @threads = []
      @semaphore = Mutex.new
    end
  
    def command(cmd, pipe, *params)
      Thread.current[:command] = cmd
      pipe.syswrite("#{cmd} #{params.join(' ')}\n")
    end
  
    def listen(pipe, try = 0)
      answer = (pipe.sysread(30) || '').strip
  
      if answer == 'proxy'
        raise "Broken url: #{Thread.current[:url]}" if try > @tries
      
        proxy = getProxy
        log "Choosing new proxy: #{(proxy || 'nil').yellow}", pipe
        command :proxy, pipe, proxy
        command :url, pipe, Thread.current[:url]
        listen pipe, try+1
      elsif answer.empty?
        raise "Empty answer from worker process"
      elsif answer == 'timeout' || answer == 'error'
        raise "Process: '#{answer}'"
      elsif Thread.current[:command] == :url
        log "Process: #{Thread.current[:url].cyan}: '#{answer.green}'", pipe
      else
        log "Answer: #{answer}".green, pipe
      end
    end
  
    def worker
      IO.popen("#{@script}", 'r+') { |p|
        proxy = getProxy
        log "Starting loop with new proxy: ".green + "#{(proxy || 'nil').yellow}", p
        command :proxy, p, proxy
      
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
              command :url, p, url
              listen p
            end
          end
        
          log "Finishing loop".green, p
        rescue Exception => e
          @semaphore.synchronize {
            log "Exception in main: " + "#{e.message.red}, '#{Thread.current[:url]}'".red, p
            command :exit, p
            #puts e.backtrace
          }
        end
      }
    
      if @urls.length > 0
        # @threads << Thread.new(&(->{worker}))
        # @threads.last.join
        worker
      end
    end
  
    def start
      puts "[main] Starting " + "#{@workers}".yellow + " workers:"
      @workers.times { |i| @threads << Thread.new(&(->{worker})) }
      @threads.each { |t| t.join }
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
      unless pipe.nil? then puts "[#{pipe.pid}]".blue + " #{msg}"
      else puts msg end
    end
  end
end