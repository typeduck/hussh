###############################################################################
# Tets the hussh SSH2 wrapper
###############################################################################

path = require("path")
fs = require("fs")

hussh = require("./hussh")
CONFIG = require("convig").env({
  HUSSHHOST: () -> throw new Error("HUSSHHOST required for test")
  HUSSHUSER: () -> throw new Error("HUSSHUSER required for test")
  HUSSHKEYFILE: () -> throw new Error("HUSSHKEYFILE required for test")
  HUSSHTEMPLOCAL: () -> path.resolve(__dirname, "../tmp")
  HUSSHLOGFILE: () -> "#{@HUSSHTEMPLOCAL}/hussh-test.log"
  HUSSHTEMPREMOTE: "hussh-tmp"
})

should = require("should")

describe "hussh", () ->

  client = null
  before () ->
    privateKey = require("fs").readFileSync(CONFIG.HUSSHKEYFILE)
    sshOpts =
      hostname: CONFIG.HUSSHHOST
      username: CONFIG.HUSSHUSER
      privateKey: privateKey
    opts =
      encoding: "utf-8"
      logFile: CONFIG.HUSSHLOGFILE
    client = hussh(sshOpts, opts)
  after (done) -> client.disconnect(done)

  it "should be able to make temporary directory", (done) ->
    client.exec("mkdir -p #{CONFIG.HUSSHTEMPREMOTE}", done)

  it "should connect to SSH server", (done) ->
    @timeout(5000)
    text = "hello, world: #{new Date()}\n"
    fnLocal = "#{CONFIG.HUSSHTEMPLOCAL}/hello.txt"
    fnRemote = "#{CONFIG.HUSSHTEMPREMOTE}/hello.txt"
    client.uploadString text, fnRemote, (err) ->
      return done(err) if err
      client.download(fnRemote, fnLocal, done)

  it "should handle ENV vars (and quote them for bash)", (done) ->
    @timeout(5000)
    env = {FOO: "a\"b\\c'd e!f?g$h@i*j~k|l`m"}
    client.execBuffer "env", env, (err, buffered) ->
      return done(err) if err
      stdout = buffered.stdout.split(/\r\n|\r|\n/)
      fooline = stdout.filter((s) -> /^FOO=/.test(s))[0]
      "FOO=#{env.FOO}".should.equal(fooline)
      done(err)

  it "should give us an error for a bad command", (done) ->
    cmd = "mkdir #{CONFIG.HUSSHTEMPREMOTE}/this/should/fail"
    client.execStatus cmd, (err, res) ->
      (err instanceof Error).should.be.true()
      done()

  it "should give us return status OK for good execStatus", (done) ->
    cmd = "ls #{CONFIG.HUSSHTEMPREMOTE}"
    client.execStatus cmd, (err) ->
      done(err)

  it "should be able to connect/disconnect/re-connect", (done) ->
    client.execBuffer "ls", (err, res) ->
      return done(err) if err
      client.disconnect () ->
        client.execBuffer "ls", (err, res2) ->
          return done(err) if err
          res.stdout.should.equal(res2.stdout)
          done()

# Promise API
describe "hussh, Promisified", () ->
  Promise = require("bluebird")
  client = null
  before () ->
    privateKey = require("fs").readFileSync(CONFIG.HUSSHKEYFILE)
    sshOpts =
      hostname: CONFIG.HUSSHHOST
      username: CONFIG.HUSSHUSER
      privateKey: privateKey
    opts =
      encoding: "utf-8"
      logFile: CONFIG.HUSSHLOGFILE
    client = Promise.promisifyAll(hussh(sshOpts, opts))
  after (done) -> client.disconnectAsync().asCallback(done)

  it "should be able to make temporary directory", () ->
    client.execAsync("mkdir -p #{CONFIG.HUSSHTEMPREMOTE}")

  it "should connect to SSH server", () ->
    @timeout(5000)
    text = "hello, world: #{new Date()}\n"
    fnLocal = "#{CONFIG.HUSSHTEMPLOCAL}/hello.txt"
    fnRemote = "#{CONFIG.HUSSHTEMPREMOTE}/hello.txt"
    client.uploadStringAsync(text, fnRemote).then(() ->
      client.downloadAsync(fnRemote, fnLocal)
    )

  it "should handle ENV vars (and quote them for bash)", () ->
    @timeout(5000)
    env = {FOO: "a\"b\\c'd e!f?g$h@i*j~k|l`m"}
    client.execBufferAsync("env", env).then((buffered) ->
      stdout = buffered.stdout.split(/\r\n|\r|\n/)
      fooline = stdout.filter((s) -> /^FOO=/.test(s))[0]
      "FOO=#{env.FOO}".should.equal(fooline)
    )

  it "should give us an error for a bad command", () ->
    cmd = "mkdir #{CONFIG.HUSSHTEMPREMOTE}/this/should/fail"
    client.execStatusAsync(cmd).then(() ->
      throw new Error("BADERROR")
    )
    .catch((err) ->
      (err instanceof Error).should.be.true()
      err.message.should.not.equal("BADERROR")
    )

  it "should give us return status OK for good execStatus", () ->
    cmd = "ls #{CONFIG.HUSSHTEMPREMOTE}"
    client.execStatusAsync(cmd)

  it "should be able to connect/disconnect/re-connect", () ->
    Promise.bind({}).then(() ->
      client.execBufferAsync("ls")
    ).then((@res) ->
      client.disconnectAsync()
    ).then(() ->
      client.execBufferAsync("ls")
    ).then((@res2) ->
      @res.stdout.should.equal(@res2.stdout)
    )
