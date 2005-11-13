# contents:
#
# Copyright © 2005 Nikolai Weibull <nikolai@bitwi.se>

require 'uri/generic'
require 'open-uri'

module URI
  # The syntax of DICT URIs is defined in RFC 2229 section 5.
  class DICT < Generic
    # :stopdoc:
    DEFAULT_PORT = 2628

    COMPONENT = [
      :scheme,
      :userinfo, :host, :port,
      :path
    ].freeze

    CLIENT_STRING = 'Ruby open-uri DICT-protocol-module'
    # :startdoc:

    # Creates a new URI::DICT object from components, with syntax checking.  
    #
    # The components accepted are +userinfo+, +host+, +port+, and +path+.
    #
    # The components should be provided either as an Array, or as a Hash with
    # keys formed by preceding the component names with a colon. 
    #
    # If an Array is used, the components must be passed in the order
    # [userinfo, host, port, path].
    #
    # ==== Examples
    #
    #   uri = URI::DICT.build(['user:password', 'dict.org', nil,
    #     '/d:word:database:1'])
    #   puts uri  # ⇒ "dict://user:password@dict.org/d:word:database:1
    #
    #   uri2 = URI::DICT.build({:userinfo => 'user:password',
    #     :host => 'dict.org', :path => '/d:word:database:1'})
    #   puts uri2 # ⇒ "dict://user:password@dict.org/d:word:database:1
    def self.build(args)
      super(Util::make_components_hash(self, args))
    end

    # Creates a new URI::FTP object from generic URL components with no syntax
    # checking.
    #
    # Arguments are +scheme+, +userinfo+, +host+, +port+, +path+, in that order.
    def initialize(*args)
      super
    end

    def buffer_open(buf, proxy, options) # :nodoc:
      if proxy
        OpenURI.open_http(buf, self, proxy, options)
        return
      end

      require '../net/dict'

      case path
      when /^\/d:([^:]+)(?::([^:]+)(?::(.+))?)?$/
        method = :define
        args = $~[1..2]
        n = $3
      when /^\/m:([^:]+)(?::([^:]+)(?::([^:]+)(?::(.+))?)?)?$/
        method = :match
        args = $~[1..3]
        n = $4
      else
        raise ArgumentError, "unknown DICT path: #{path}"
      end

      if n
        n = n.to_i
        raise ArgumentError, '<n> must be greater than zero' if n <= 0
      end

      args = args.reject{ |arg| arg.nil? }

      result, _ = Net::DICT.session(CLIENT_STRING, host, port ? port.to_i : nil) do |dict|
        dict.authenticate(*userinfo.split(/:/)) if userinfo
        dict.send(method, *args)
      end

      case method
      when :define
        if n
          buf << result.fetch(n - 1).to_s
        else
          buf << "#{result.length} definitions found\n\n"
          result.each{ |definition| buf << definition.to_s }
        end
      when :match
        # TODO: the n specifier is stupid for MATCH
        longest = result.keys.inject(0){ |m, database| [database.length, m].max }
        result.each do |database, words|
          buf << sprintf("%*s     %s\n", longest, database, words.join(', '))
        end
      end

      buf.io.rewind
    end

    include OpenURI::OpenRead
  end

  @@schemes['DICT'] = DICT
end

if __FILE__ == $0
  require 'open-uri'

  open('dict://dict.org/d:exact') do |file|
    file.each do |line|
      puts line
    end
  end
end
