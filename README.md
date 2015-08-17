# HuSSH

HuSSH is a simple wrapper for [ssh2](https://github.com/mscdex/ssh2) with only a
few simple features:

- Connects when you give it work to do
- Always passes ENV vars (by prepending them to commands)
- Simplified interface for uploading, downloading
- Simplified methods for command execution:
  - buffering stdout/stderr
  - just waiting for exit code
- Optionally logs activity to a local file
- [Tell the dog](http://www.victoriawilliams.net/tarbelly-and-featherfoot/polish-those-shoes)

If you need anything more complex than file upload/download and command
execution, use [ssh2](https://github.com/mscdex/ssh2) directly. If you don't
need/want very simplified commands, use [ssh2](https://github.com/mscdex/ssh2).

```js
var hussh = require("hussh")
var client = hussh({
  host: "example.com",
  username: "foo",
  privateKey: require("fs").readFileSync("./my-secret.key")
}, {encoding: "utf-8});

// upload a string to a remote file
client.uploadString("text for my file", "remote-file.txt", function(err){
  if ( ! err ) {
    // file contents uploaded
  }
});

// execute a command and save all buffered output
client.execBuffer("env", {MYENVVAR: "myenv-value"}, function(err, result){
  if ( ! err ) {
    // command exit status is 0, access result.stdout and result.stderr here
  }
  else {
    // command had non-zero exit status... see what happened
    console.error(err.message)
  }
});
```

## Instantiation

```js
var client = hussh(sshOptions, moreOptions);
```

- **sshOptions**: these are passed directly to ssh2.connect
  - **username**: if not set, will be set according to precedence:
    - **moreOptions.username**
    - *process.env.USER*
    - "root"
  - **host**: if not set, will be set according to precedence:
    - **moreOptions.hostname**
    - **moreOptions.host**
    - "localhost"
  - All other options (such as **privateKey**) check
    [ssh2](https://github.com/mscdex/ssh2) docs.
- **moreOptions**: these only affect hussh, not ssh2 (except as noted above)
  - **env**: ENV vars to include for all further commands
  - **encoding**: sets encoding for local log file, uploadString() method
  - **logStream**: WriteableStream for logging hussh instance activity
  - **logFile**: (only when **logStream** absent) file to log activity

## Command Execution

```js
client.exec(command, env, callback);
client.execBuffer(command, env, callback);
client.execStatus(command, env, callback);
```

- **command**: (String) command, including arguments
- **env**: (Object) if given, the environment variables will be set (prepended
  to command in KEY=value style)
- **callback**: (Function) called with the following:
  - **err**: null if OK, Error object otherwise
  - **result**: type depends the method used:
    - **exec**: ssh2 Channel (just like calling ssh2.Client.exec)
    - **execBuffer**: object with *stdout* and *stderr* Strings or Buffers
    - **execStatus**: result is omitted (undefined)

## File Upload/Download

```js
client.uploadString(stringData, remoteFile, callback);
client.upload(localFile, remoteFile, callback);
client.download(remoteFile, localFile, callback);
```

These are all just shortcuts which create an SFTP session, handle streams, and
call the callback (receives **Error** on failure).
