###############################################################################
# A remote server with SSH access. Basically a wrapper for ssh2 library with
# local logging.
###############################################################################

fs = require "fs"

assign = require("lodash.assign")
Client = require("ssh2").Client
Promise = require("bluebird")

module.exports = (sshOpts, opts) -> new hussh(sshOpts, opts)

# Helpers for always transmitting ENV vars by prefixing to command
envEscape = (s) -> s.replace(/([\"$\\`])/g, "\\$1")
envPrefix = (env) -> ("#{k}=\"#{envEscape(v)}\" " for k, v of env).join("")

class hussh
  constructor: (sshOpts, opts) ->
    @opts = assign({}, opts)
    @sshOpts = assign({}, sshOpts)
    @sshOpts.username ?= @opts.username || process.env.USER || "root"
    @sshOpts.host ?= @opts.hostname || @opts.host || "localhost"
    # Local stream to log to
    if @opts.logFile and not @opts.logStream
      @opts.logStream = fs.createWriteStream(@opts.logFile, {flags: "a"})
    # SSH/SFTP Connection
    @_ssh = null
    @_sshPromise = null
    @_sftp = null
    @_sftpPromise = null

  # Connects via SSH and saves the SSH Connection object
  connect: () ->
    Promise.try(() =>
      if @_ssh then return @_ssh
      @_sshPromise ?= new Promise((resolve, reject) =>
        client = new Client()
        cleanup = () =>
          @_sshPromise = null
          client.removeListener("ready", onReady)
          client.removeListener("error", onError)
          client.removeListener("ready", cleanup)
          client.removeListener("error", cleanup)
        onReady = () => resolve(@_ssh = client)
        onError = (e) => reject(e)
        client.on("ready", cleanup)
        client.on("error", cleanup)
        client.on("ready", onReady)
        client.on("error", onError)
        client.connect(@sshOpts)
      )
    )
  # Disonnects the SSH session
  disconnect: (done) ->
    return done?() if not @_ssh and not @_sshPromise
    if typeof done isnt "function" then done = ( -> )
    @connect().then((ssh) =>
      cleanup = () =>
        @_ssh = null
        @_sftp = null
        @_sshPromise = null
        @_sftpPromise = null
      ssh.once("close", cleanup)
      ssh.once("close", done).end()
    ).catch(done)
  
  # Optional logging, only if logFile and logStream are set
  logCommand: ( cmd ) -> @log("Command: #{cmd}")
  logUpload: (fnLoc, fnRemote) -> @log ("Uploading #{fnLoc} --> #{fnRemote}")
  # Logging method
  log: (s) ->
    return if typeof @opts.logStream?.write isnt "function"
    @opts.logStream.write("[#{new Date()}] #{s}\n", "ascii")
  
  # Starts an SFTP session if one is not in progress
  sftpSession: () ->
    Promise.try(() =>
      if @_sftp then return @_sftp
      @_sftpPromise ?= @connect().then((ssh) =>
        doit = Promise.promisify(ssh.sftp, {context: ssh})
        doit().then((sftp) =>
          return @_sftp = sftp
        )
      ).finally(() => @_sftpPromise = null)
    )

  # Fixes the arguments passed to exec
  _execArgs: (args) ->
    ret = {env: assign({}, @opts.env), done: (->), cmd: null}
    while (arg = args.shift())
      switch typeof arg
        when "string" then ret.cmd = arg
        when "function" then ret.done = arg
        when "object" then assign(ret.env, arg)
    return ret
  
  # Embellishes a command stream exit status
  getError: (code, cmd, env) ->
    return null if not code
    msg = "Command '#{cmd}', exit status #{code}, env=" + JSON.stringify(env)
    return new Error(msg)
  
  # Executes a command on the remote server, with environment. Note that the
  # ssh2.exec() with env does not setup environment variables (according to our
  # tests)
  exec: (args...) ->
    task = @_execArgs(args)
    cmdLong = envPrefix(task.env) + task.cmd
    # Ensure we are connected, then execute command, piping to log
    @connect().then((ssh) =>
      @logCommand( cmdLong )
      ssh.exec cmdLong, (err, stream) =>
        return task.done?(err) if err
        if @opts.encoding
          stream.setEncoding(@opts.encoding)
          stream.stderr.setEncoding(@opts.encoding)
        if @opts.logStream
          stream.pipe(@opts.logStream, {end: false})
          stream.stderr.pipe(@opts.logStream, {end: false})
        task.done?(null, stream)
    ).catch(task.done)
  
  # Simplified execution: when we want access to the output, but not streaming
  # access, so we request buffering of stdout and stderr streams and return them
  # when it's over
  execBuffer: (args...) ->
    task = @_execArgs(args)
    # Create stdout, stderr buffers to stream into, function to compact later
    buf = {stdout: [], stderr: []}
    compactBuffer = (p) ->
      isBuffer = buf[p].length and Buffer.isBuffer(buf[p][0])
      buf[p] = if isBuffer then Buffer.concat(buf[p]) else buf[p].join("")
    # Execute command, capture data, call when finished
    @exec task.cmd, task.env, (err, stream) =>
      return task.done?(err) if err
      stream.on "data", (s) -> buf.stdout.push(s)
      stream.stderr.on "data", (s) -> buf.stderr.push(s)
      stream.on "exit", (code) =>
        compactBuffer(prop) for prop in ["stdout", "stderr"]
        task.done?(@getError(code, task.cmd, task.env), buf)
  
  # Simplified execution: when we want only access to the status code, not the
  # stream, and only want to get called on stream exit
  execStatus: (args...) ->
    task = @_execArgs(args)
    @exec task.cmd, task.env, (err, stream) =>
      return task.done?(err) if err
      stream.on "exit", (code) =>
        task.done?(@getError(code, task.cmd, task.env))

  # File Upload/Download
  upload: (fnLocal, fnRemote, done) ->
    @log("Uploading #{fnLocal} --> #{fnRemote}")
    @sftpSession().then (sftp) -> sftp.fastPut(fnLocal, fnRemote, done)
  download: (fnRemote, fnLocal, done) ->
    @log("Downloading #{fnRemote} --> #{fnLocal}")
    @sftpSession().then (sftp) -> sftp.fastGet(fnRemote, fnLocal, done)
  
  # For uploading an in-memory string as a file
  uploadString: (sData, fnRemote, done) ->
    @log("Uploading #{sData.length}-char string --> #{fnRemote}")
    opts = if @opts.encoding then {encoding: @opts.encoding} else {}
    @sftpSession().then((sftp) ->
      stream = sftp.createWriteStream(fnRemote, opts)
      stream.once("error", done)
      stream.end(sData, done)
    ).catch(done)
