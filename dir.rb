#!/usr/bin/env ruby

require 'ftools'
require 'fileutils'
require 'pathname'
require 'rubygems'
require 'thin'


class DirServ
  def initialize(docroot=FileUtils.pwd)
    @docroot = docroot
  end

  def call(env)
    request_path = env['REQUEST_PATH']
    puts request_path.inspect
    real_path = File.join(@docroot,request_path)
    if File.directory?(real_path)
      files = Dir["#{real_path}/*"]
      output = "<html><head><title>#{request_path}</title></head><body><ul>"
      rootp = Pathname.new(@docroot)
      files.each do|f|
        fp = Pathname.new(f)
        rp = fp.relative_path_from(rootp)
        puts "link to #{f} => #{rp}"
        output << %(<li><a href="#{rp}">#{File.basename(f)}</a></li>)
      end
      output << "</ul></body></html>"

      [200,{'Content-Type' => "text/html"}, output]
    elsif File.exist?(real_path)
      if request_path.match(/\/$/)
        real_path = File.join(real_path,"index.html")
      end
      ext = File.extname(real_path)
      content_type = case ext
      when '.css' then 'text/css'
      when '.js' then 'application/x-javascript'
      when '.html' then 'text/html'
      when '.rb' then 'text/plain'
      when '.png' then 'image/png'
      when '.jpg' then 'image/jpeg'
      when '.gif' then 'image/gif'
      else
        'application/octet-stream'
      end
      [200,{'Content-Type' => content_type}, File.read(real_path) ]
    else
      [404,{'Content-Type' => content_type}, "File not found" ]
    end
  end
end

require 'getoptlong'
begin
  require 'rdoc/usage'
rescue LoadError => e
  STDERR.puts "--help, -h requires rdoc"
end

class App
  def initialize

    @opts = GetoptLong.new(
      [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
      [ '--port', '-p', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--daemonize', '-d', GetoptLong::NO_ARGUMENT ],
      [ '--pid', '-P', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--log', '-l', GetoptLong::REQUIRED_ARGUMENT ],
      [ '--kill', '-k', GetoptLong::NO_ARGUMENT ]
    )
    @port      = 3000
    @daemonize = false
  end

  def execute
    @pid_file = nil
    @log_file = nil

    @opts.each do |opt, arg|
      case opt
      when '--help'
        if defined?(RDoc)
          RDoc::usage
        else
          STDERR.puts "missing ruby rdoc"
        end
        exit(0)
      when '--daemonize'
        @daemonize = true
      when '--pid'
        @pid_file = arg
        if !@pid_file.match(/^\//)
          STDERR.puts "pid file path must be absolute"
          exit(1)
        end
      when '--log'
        @log_file = arg
        if !File.exist?(File.dirname(@log_file))
          STDERR.puts "error missing log file folder!"
          exit(1)
        end
      when '--port'
        @port = arg.to_i
        puts "port: #{arg} and #{arg.to_i}"
      when '--kill'
        if File.exist?("#{@docroot}/rthttpd.pid")
          Process.kill("TERM",File.read("#{@docroot}/rthttpd.pid").to_i)
        elsif File.exist?(@pid_file)
          Process.kill("TERM",File.read(@pid_file).to_i)
        else
          STDERR.puts("No pid file found at #{@docroot}/rthttpd.pid")
        end
        exit(0)
      end
    end

    @pid_file = "#{@docroot}/rthttpd.pid" if @pid_file.nil? and @daemonize

    run_server
  end

  def run_server

    rthttpd = Rack::URLMap.new('/'  => DirServ.new() )

    puts "Loading server on port: #{@port} with #{@pid_file}"

    server = Thin::Server.new('127.0.0.1', @port, rthttpd)

    puts "Logging to: #{@log_file.inspect}"

    server.log_file = @log_file if @log_file
    server.pid_file = @pid_file if @pid_file

    if @daemonize
      # daemonized we need a log file path
      server.log_file = "#{@docroot}/rthttpd.log"
      server.daemonize
    end
    server.start
  end

  # log messages
  def log(msg)
    STDERR.puts msg
  end
end

if $0 == __FILE__
  app = App.new
  app.execute
end
