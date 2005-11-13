# contents:
#
# Copyright © 2005 Nikolai Weibull <nikolai@bitwi.se>
#
# See Net::DICT for an overview.

require 'net/protocol'
require 'digest/md5'
require 'stringio'

module Net
  # Represents an unrecognized reply from the server; will be raised whenever a
  # reply other than the one expected was returned.  This should indicate a
  # bogus server implementation.
  class DICTReplyError < ProtoUnknownError; end

  # Represents a completely bogus reply from the server.  This includes
  # illegal response codes and responses without a response code.
  class DICTUnknownError < ProtoUnknownError; end

  # Represents errors caused by a temporary situation, such as a server reboot
  # or software update.  Trying the same request at a later time should work
  # fine.
  class DICTRetriableError < ProtoRetriableError; end

  # Represents errors relating to server commands.  This may be caused by
  # calling a command not supported by the server, calling a command with
  # illegal parameters, or something similar.
  class DICTSyntaxError < ProtoSyntaxError; end

  # Represents errors pertaining to authorization failures; see
  # DICT#authenticate.
  class DICTAuthError < ProtoAuthError; end

  # Represents errors pertaining to server-system resources, such as missing
  # databases, strategies, and definitions.
  class DICTSystemError < ProtoServerError; end

  # Represents the fact that no match/definition could be found in any of the
  # databases (using the given strategy) on the server; see DICT#match and
  # DICT#define.
  class DICTNoMatchError < DICTSystemError; end

  # Represents the fact that no databases could be found on the server; see
  # DICT#databases.
  class DICTNoDatabasesError < DICTSystemError; end

  # Represents the fact that no strategies could be found on the server; see
  # DICT#strategies.
  class DICTNoStrategiesError < DICTSystemError; end

  # == Introduction
  #
  # This class implements the client side of the Dictionary Server Protocol
  # (DICT) described in [RFC2229] (http://ietf.org/rfc/rfc2229.txt).
  #
  #
  # == Examples
  #
  # === Defining a Word
  #
  #    require 'net/dict'
  #
  #    dict = Net::DICT.new('dict.org')
  #    dict.client = 'Ruby-Net::DICT example'
  #    puts dict.define('ruby', 'foldoc')[0]
  #    dict.disconnect
  #
  # === Defining a Word Using a Pipeline
  #
  #    require 'net/dict'
  #
  #    dict = Net::DICT.new
  #    definitions, _ = dict.pipeline do
  #      dict.connect('dict.org')
  #      dict.client = 'Ruby-Net::DICT pipeline example'
  #      dict.define('ruby', 'foldoc')
  #      dict.disconnect
  #    end
  #    puts definitions[0]
  #
  # === Matching a Pattern
  #
  #   require 'net/dict'
  #
  #   dict = Net::DICT.new
  #   matches, _ = dict.pipeline do
  #     dict.connect('dict.org')
  #     dict.client = 'Ruby-Net::DICT match example'
  #     dict.match('ruby', 'foldoc', 'soundex')
  #     dict.disconnect
  #   end
  #   puts matches['foldoc']
  #
  # === Getting a List of Databases
  #
  #   require 'net/dict'
  #
  #   dbs, _ = Net::DICT.session('Ruby-Net::DICT db example', 'dict.org') do |dict|
  #     dict.databases
  #   end
  #   dbs.each{ |db, description| puts "#{db}: #{description}" }
  #
  # === Using open-uri to Retrieve Textual Definitions
  #
  #   require 'net/dict'
  #   require 'uri/dict'
  #   require 'open-uri'
  #
  #   open('dict://dict.org/d:word'){ |file| puts file.read }
  #
  # == Errors
  #
  # All methods that talk to the server may raise any of the following errors:
  #
  # [DICTRetriableError]
  #   Represents errors caused by a temporary situation, such as a server
  #   reboot or software update.  Trying the same request at a later time
  #   should work fine.
  # [DICTSyntaxError]
  #   Represents errors relating to server commands.  This may be caused by
  #   calling a command not supported by the server, calling a command with
  #   illegal parameters, or something similar.
  # [DICTSystemError]
  #   Represents errors caused by trying to access non-existent database, using
  #   unsupported matching-strategies, or some other server-specific error.
  class DICT
    # The database name that represents the fact that all databases should be
    # searched
    DATABASE_ALL = '*'

    # The database name that represents the fact that all databases should be
    # searched until a match is found
    DATABASE_FIRST = '!'

    # The default port used when connecting to a server
    DEFAULT_PORT = 2628

    # The default database to use for #define and #match
    DEFAULT_DATABASE = DATABASE_ALL

    # The default strategy to use for #match (server-dependent
    # best-for-spell-checking default)
    DEFAULT_STRATEGY = '.'

    # Connects to the given host and port.  Then, registers you as using the
    # given #client and possibly authenticates[#authenticate] you to the
    # server.  Then you will be passed the DICT instance so that you can
    # execute further commands on the server (by invoking the appropriate
    # methods) in a block.  These commands will be executed in a #pipeline a
    # and the result of this method is therefore the result of the #pipeline.
    # After the passed block returns, you will be disconnected[#disconnect]
    # from the server.
    #
    # The idea is that a whole session with a DICT server is contained in one
    # method call and the block that is passed to it, so you won’t need to
    # worry about the details of connecting, setting your client,
    # authenticating yourself, and disconnecting when you are done.
    #
    # ==== Notes
    #
    # As #authenticate will be called on the server if you provide the relevant
    # data, you should be certain that the server supports this particular
    # command, as an error will be raised otherwise.  You can check if a server
    # supports this command through the #authentication? method, but by then it
    # will be too late, as #authenticate will be called _before_ you receive
    # the DICT instance.  If you want to verify that the server supports
    # authentication, you can write code like that in the second example below.
    # Almost all servers support authentication, but it’s always good to play
    # it safe.
    #
    # ==== Examples
    #
    #   dbs, _ = Net::DICT.session('Ruby-Net::DICT session example', 'dict.org') do |dict|
    #     dict.databases
    #   end
    #   dbs.each{ |db, description| puts "#{db}: #{description}" }
    #
    #   ds, _ = Net::DICT.session('Ruby-Net::DICT authenticated-session example', 'dict.org') do |dict|
    #     dict.authenticate('pea-tear', 'griffin') if dict.authenication?
    #     dict.define('word', 'well-protected-database')
    #   end
    #   ds.each{ |d| puts d }
    def self.session(client, host, port = DEFAULT_PORT, user = nil, secret = nil)
      (dict = self.new).pipeline do |dict|
        dict.connect(host, port)
        dict.client = client
        dict.authenticate(user, secret) if user and secret
        yield dict
        dict.disconnect
      end
    ensure
      dict.close
    end

    # Creates a new DICT object.  If a host is provided, then a
    # connection[#connect] to that server is also established, and if a user
    # and secret is provided, then authentication[#authenticate] will also be
    # done.
    def initialize(host = nil, port = DEFAULT_PORT, user = nil, secret = nil)
      if host
        connect(host, port)
        authenticate(user, secret) if user and secret
      end
    end

    # Establishes a connection to the given host on the given port.  The port
    # defaults to DEFAULT_PORT, so it can usually be elided.
    #
    # ==== Notes
    # 
    # Only after connection has been established to a server will the
    # #capabilities of the server be known, so you shouldn’t use that method
    # nor the #authentication? method before doing so.
    def connect(host, port = DEFAULT_PORT)
      @socket = TCPSocket.open(host, port)
      @output = @socket unless @output
      r = response().join(' ')
      if m = /^220\s.*?(?:<(#{MsgAtoms})>\s)?(<#{MsgAtoms}@#{MsgAtoms}>)$/.match(r)
        @capabilities, @msgid = (m[1] ? m[1].split(/\./) : []), m[2]
      else
        raise DICTReplyError, r
      end
    end

    # An array of server-dependent capabilities (expressed as strings) of the
    # server.  There are however some defined by RFC2229 that may be of
    # interest; see [RFC2229] (http://ietf.org/rfc/rfc2229.txt), Section 3.1.
    attr_reader :capabilities

    # Returns +true+ iff the server supports authentication.  If it does, the
    # #authenticate command may be used.
    def authentication?
      @capabilities and @capabilities.include? 'auth'
    end

    # Authenticate ourselves to the server as the given 'user' using the given
    # secret (password).
    #
    # ==== Notes
    # 
    # Most servers are completely open to everyone, and most servers have at
    # least some databases that are accessible by everyone, so authentication
    # is rarely needed.  Should a server host databases that are unaccessible
    # without authentication, however, this is the method to call.  The secret
    # (password) is sent as an MD5 digest of a message-id sent as a response by
    # the server upon connection concatenated with the actual secret, so there
    # is (still) little to worry about in terms of security.
    #
    # ==== Errors
    #
    # This method will raise a Net::DICTAuthError if access was denied (i.e.,
    # authentication failed).
    def authenticate(user, secret)
      command 'AUTH', user, Digest::MD5.hexdigest(@msgid + secret) do
        response 230
      end
    end

    # Close the connection to the server.  You may later open a new
    # connection with #connect.
    def close
      @socket.close unless closed?
    end

    # Returns +true+ iff there is no connection to a server.
    def closed?
      @socket.nil? or @socket.closed?
    end

    # Disconnect from the server by first issuing a quit command to it and then
    # closing[#close] the connection.
    def disconnect
      command 'QUIT' do
        begin
          response 221
        ensure
          close
        end
      end
    end

    # Request a list of MetaData about the databases on the server.
    #
    # ==== Errors
    #
    # This method will raise a Net::DICTNoDatabasesError if no databases are
    # present on the server.  Thus, the return value will always contain at
    # least one MetaData element.
    #
    # ==== Example
    #
    #   dict.databases.each{ |db| puts "#{db.name}: #{db.description}" }
    def databases
      command 'SHOW DATABASES' do
        response 110
        metadata
      end
    end

    # Request a list of MetaData about the matching strategies that the server
    # supports.  These are the valid arguments for the strategy parameter to
    # the #match method.
    #
    # ==== Errors
    #
    # A Net::DICTNoStrategiesError will be raised if no strategies are
    # supported by the server.  Thus, the return value will always contain at
    # least one MetaData element.
    #
    # ==== Example
    #
    #   dict.strategies.each{ |strat| puts "#{strat.name}: #{strat.description}" }
    def strategies
      command 'SHOW STRATEGIES' do
        response 111
        metadata
      end
    end

    # Request information about a given database on the server.  The result
    # is a String of free-form text that may include information about the
    # source, copyright, and license of the database.
    #
    # ==== Example
    #
    #   puts dict.info('foldoc')
    def info(database)
      command 'SHOW INFO', database do
        response 112
        text
      end
    end

    # Request a summary of the commands supported by the server.  The result is
    # a String containing free-form text.
    # 
    # ==== Example
    #
    #   puts dict.help
    def help
      command 'HELP' do
        response 113
        text
      end
    end

    # Request information about the server itself.  The result is a String
    # containing free-form text that may include information about databases
    # and strategies supported by the server, or administrative information
    # such as who to contact for access to databases requiring authentication.
    #
    # ==== Example
    #
    #   dict.server # ⇒ "dictd 1.9.15/rf on Linux 2.4.27-2-k7 …"
    def server
      command 'SHOW SERVER' do
        response 114
        text
      end
    end

    # This method should be called by all clients after connecting to a server
    # with information about the client for logging and statistical purposes.
    #
    # ==== Example
    #
    #   dict.client('Ruby-Net::DICT-class #client-method-documentation example-client')
    def client(client)
      command 'CLIENT', client.to_str.inspect do
        response 250
      end
    end

    # This method is an alias for #client for those of us who find that this
    # specific command feels more like an assignment than an actual
    # client/server transaction.
    #
    # ==== Example
    #
    #   dict.client = 'Ruby-Net::DICT-class #client-method-documentation example-client'
    def client=(client)
      client(client)
    end

    # Request some server-specific timing or debugging information.  This
    # information is usually only interesting to a server developer or a server
    # maintainer.
    #
    # ==== Example
    #
    #   dict.status # ⇒ "status [d/m/c = 0/0/0; 0.000r 0.000u 0.000s]"
    def status
      command 'STATUS' do
        response[1]
      end
    end

    # Request a hash of database-names to lists-of-words matching the given
    # word in the given databases, using the given strategy.
    #
    # ==== Errors
    #
    # This method raises a Net::DICTNoMatchError if no matches are found.
    # Thus, the returned hash will contain at least one database-name to
    # list-of-words.
    #
    # ==== Example
    # 
    #   dict.match('rub', 'foldoc', 'prefix') # ⇒ {"foldoc"=>["rubi", "ruby"]}
    def match(word, database = DEFAULT_DATABASE, strategy = DEFAULT_STRATEGY)
      command 'MATCH', database, strategy, word.to_str.inspect do
        response 152
        hash
      end
    end

    # Request a list of Definitions[Definition] of the given word in the given
    # databases.
    #
    # ==== Errors
    #
    # If no matches are found, a Net::DICTNoMatchError is raised.  Thus, the
    # returned list will contain at least one Definition.
    #
    # ==== Example
    #
    #   dict.define('ruby', 'foldoc').each{ |definition| puts definition }
    def define(word, database = DEFAULT_DATABASE)
      command 'DEFINE', database, word.to_str.inspect do
        response 150
        definitions
      end
    end

    # Sets up a pipeline for sending commands en masse to the server.  Once the
    # pipeline has been established, the object that this method was invoked
    # upon will be passed to the given block.  After that block returns, all
    # the commands executed in that block will be shipped off to the server in
    # one fell swoop.  This saves both us and the server some traffic, and can
    # improve response-times considerably.  It is therefore recommended that
    # you do most of your work in a pipeline.  This can be done completely
    # transparently by using the ::session method.
    #
    # The result of this method is a list of all the non-nil results returned
    # by the server.  For example, if you first request a list of databases on
    # the server and then request the definitions of the words “definition” and
    # “word”, you’ll get a list containing a MetaData object, followed by two
    # Definition objects.
    #
    # ==== Notes
    #
    # This method isn’t thread-safe.
    #
    # ==== Example
    #
    #   databases, definition, word = dict.pipeline do |dict|
    #     dict.databases
    #     dict.define('definition')
    #     dict.define('word')
    #   end
    def pipeline
      @output = StringIO.new
      @pipeline = []
      yield self
      @output.rewind
      @socket.print(@output.read)
      @output = @socket
      values = []
      @pipeline.each do |block|
        value = block.call
        values << value if value
      end
      values
    ensure
      @output = @socket
      @pipeline = nil
    end

    # Represents a definition of a word in a database as returned by the
    # server.  It includes the word itself, its definition, and the name and
    # description of the database in which the definition was found.
    class Definition
      def initialize(metainfo, definition) # :nodoc:
        @word, @database, @description = metainfo
        @definition = definition
      end

      # Returns a String representation of the definition prefixed with
      # information about the database it was found in.
      def to_s
        "From #{@description} [#{@database}]:\n\n" +
        "#{@definition.inject(''){ |s, l| s << '  ' << l }}\n\n"
      end

      # The word that this definition pertains to
      attr_reader :word

      # The name of the database that this definition was found in
      attr_reader :database

      # The description of the database that this definition was found in
      attr_reader :description

      # The actual definition of the word that this definition pertains to
      attr_reader :definition
    end

    # Represents metadata about a resource on the server, such as databases and
    # strategies; see DICT#databases and DICT#strategies.
    class MetaData
      def initialize(name, description) # :nodoc:
        @name, @description = name, description
      end

      # Returns a String representation – _name_: _description_ – of this piece of
      # metadata.
      #
      # ==== Example
      #
      #   dbs = dict.databases  # ⇒ [#<Net::DICT::MetaData:0xdeadbeef …>, …]
      #   dbs[rand(dbs.length)] # ⇒ "eng-swe: English-Swedish Freedict dictionary"
      def to_s
        "#{name}: #{description}"
      end

      # The name of the resource
      attr_reader :name

      # The description of the resource
      attr_reader :description
    end

  private

    # :stopdoc:

    # Lookup table for the _x_ and _y_ parts of a response code (_xy_z).
    XYToError = {
      '42' => DICTRetriableError,
      '50' => DICTSyntaxError,
      '53' => DICTAuthError,
      '55' => DICTSystemError
    }

    # Lookup table for the _x_, _y_, and _z_ parts of a response code.
    XYZToError =
      {
      '552' => DICTNoMatchError,
      '554' => DICTNoDatabasesError,
      '555' => DICTNoStrategiesError
    }

    # The RFC defines these as the parts of the capabilities and message-id
    # strings returned by the server upon initial connection.
    MsgAtom = /[^ [:cntrl:]<>.\\]+/
    MsgAtoms = /#{MsgAtom}(?:\.#{MsgAtom})*/

    # :startdoc:

    # Send a command request to the server, or chain it in the current
    # pipeline.
    def command(command, *args, &block)
      @output.print(command, args.size > 0 ? ' ' : '', args.join(' '), "\r\n")
      if block
        if @pipeline
          @pipeline << block
        else
          block.call
        end
      end
    end

    # Collect a list of metadata from the server.
    def metadata
      hash.inject([]){ |list, data| list << MetaData.new(data[0], data[1][0]) }
    end

    # Collect a list of definitions from the server.
    def definitions
      definitions = []
      while (code, parameters = response) and code != 250
        definitions << Definition.new(split(parameters), lines(false).join("\n"))
      end
      definitions
    end

    # Collect a multi-line String from the server.
    def text
      lines.join("\n")
    end

    # Collect a list of Strings from the server.  It will also eat the expected
    # 250 response by default.
    def lines(eat_response = true)
      lines = []
      while line = @socket.readline.chomp!("\r\n")
        break if line == '.'
        lines << (line[0] == ?. ? line[1..-1] : line)
      end
      response 250 if eat_response
      lines
    end

    # Collect a list of lists (usually pairs) from the server.
    def lists
      lines.inject([]){ |lists, line| lists << split(line) }
    end

    # Collect a hash of key to lists-of-values from the server.
    def hash
      lists.inject({}){ |hash, p| hash[p[0]] ||= []; hash[p[0]] << p[1]; hash }
    end

    # Read a a response from the server.  If a code is given, then check that
    # the response code matches that code.  Nil will be returned in this case,
    # so that commands that simply eat their expected server response won’t
    # produce any output in a pipeline.  If no code is given, then we simply
    # verify that the response code isn’t an error, temporary or otherwise, and
    # return the code and response-text.
    def response(code = nil)
      response = @socket.readline.chomp!("\r\n")
      if code
        raise DICTUnknownError unless m = /^\d{3}/.match(response)
        raise DICTReplyError, response unless m[0].to_i == code
        nil
      else
        raise DICTUnknownError unless m = /^(\d{3})\s(.*)/.match(response)
        if m[1] =~ /^[45]/
          raise XYZToError[m[1]] if XYZToError.include? m[1]
          raise XYToError[m[1]] if XYToError.include? m[1][0..1]
          raise DICTUnknownError, response
        end
        [m[1].to_i, m[2]]
      end
    end

    # Split the given line into its constituent words.  A word is either a
    # sequence of non-white-space characters, or a quoted (“"” or “'”) string.
    # TODO: Oniguruma’s named captures don’t work well yet
    def split(line)
      list = []
      while m = /"(?<s>[^"\\]*(?:\\.[^"\\]*)*)"|
                 '(?<s>[^'\\]*(?:\\.[^'\\]*)*)'|
                  (?<s>\S+)/x.match(line)
        list << m.captures.find{ |s| not s.nil? }
        line = m.post_match
      end
      list
    end
  end
end
