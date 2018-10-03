# Pusher

Very simple IPC queue accessed by HTTP. Written in pure LuaJIT + LuaSocket (uses no other libraries). Partly inspired by [beanstalkd](https://beanstalkd.github.io/) and [mosquitto](http://www.mosquitto.org/).

## Basic concepts

Pusher runs as a server on a chosen port. Pusher can manage any number of channels. Each channel is identified by alphanumeric string. Each chanel acts as a queue (FIFO) of messages. A message can be anything. It's just a sequence of bytes, Pusher doesn't care what it represents. Each message has globally unique id which is used for deleting it. A message cannot be empty.

Application X pushes message into channel. Application Y gets the message from the channel, handles it and - if the handling is succesful - deletes it from the channel. Deleting can also happen automatically when geting the message.

## Interface

Pusher is designed to be called from scripts using wget or curl and handling the returned data as a stream (i.e. redirecting the curl output into script's input stream). Request parameters are sent in the URL (not as the GET parameters but right in the URL), separated by a comma. For example see this basic command (assuming that Pusher is running at myserver.com at port 8000):

   curl 'myserver.com:8000/push,channel=MyChannel,message=HelloWorld'

This pushes the message 'HelloWorld' (10 bytes) to channel 'MyChannel'. The response (best parsed as lines) will be:

```
ID
abc123
DONE
```

Where "'abc123" is the unique ID of this new message.

"DONE" final line always indicates succesful completion of the operation. You can close the connection.

When returned instead of "DONE", the line "ERROR: <ErrorMessage>" indicates that something went wrong.

Lines are separated by CRLF ("\r\n") sequence.

## Commands and parameters:

### push,[channel=ChannelId,][message=MessageData,][no_id,]

Pushes a message with content MessageData to channel ChannelId and returns its assigned id. If `channel` is omitted, channel named "default" is assumed. Channel ids are alphanumeric, including the "-" character. They are case-sensitive.

If `no_id` is present, the id is not returned (only "DONE").

If `message` parameter is omitted (because the message is too long for URL or contains weird non-printable data), it must be attached as a body of the request. In this case, *don't put any other data (e.g. CRLF) after the body*. The correct example is e.g. (message read from file):

	curl -H 'Expect:' 'myserver.com:8000/push,channel=MyChannel --data-binary @datafile.bin'

Or like this (message read from stdin):

	curl -H 'Expect:' 'myserver.com:8000/push,channel=MyChannel --data-binary @-'

Note that when using curl, the `-H 'Expect:'` option is necessary when sending message longer than 1024 bytes to prevent sending Expect:100 header and splitting the upload! See the explanation [here](https://gms.tf/when-curl-sends-100-continue.html).

### get,[channel=ChannelId,][no_id,][no_age,][all,][autodelete,]

Returns the first message from channel ChannelId. The message is *not automatically deleted* (by default) and must be deleted using `delete` option. The typical succesful response may look as follows:

```
MESSAGE
10
HelloWorld
ID
abc123
AGE
600
DONE
```

I.e. first the string "MESSAGE", then CRLF, then the length of the message (in bytes), then CRLF, then the raw message data, then CRLF, then the string "ID", then CRLF, the message id, then CRLF, then the string "AGE", then CRLF, then the age of the message (in seconds), then CRLF, then the string "DONE" and finally CRLF.

Important: Note that the length of message body is given *without* the trailing CRLF! You have to skip these two bytes manually after you read the message body using fd:read(messageLength). If you are absolutely sure that message is clean string without line breaks, you can ignore the returned length and read the message using the plain fd:read() (as a text line).

If there are no messages in the channel, only "DONE" is returned.

If `all` option is present, all messages in the relevant queue are returned (from oldest to newest, each with its ID and AGE). "DONE" is output only once, after the last message.

If `autodelete` is present, all retrieved messages are automatically deleted from the channel.

If `no_id` is present, no message ids are returned.

If `no_age` is present, no message ages are returned.

### download,[channel=ChannelId,]

This is a special form of `get` command. When used, *only the message body* is returned, as a standard HTTP response. Mime-Type is not set. `download` automatically implies `autodelete`, `no_id` and `no_age` options. `download` automatically disables `all` option. For example:

	curl 'myserver.com:8000/download,channel=MyChannel' -o data.bin'

This shell command saves the first available message of channel MyChannel into file data.bin.

If there is no message available in the specified channel, HTTP error 404 is returned. That means you can e.g. use the following command to wait until a message is available and then download it to file data.bin and continue script execution.

	wget 'myserver.com:8000/download,channel=MyChannel' -o data.bin --retry-on-http-error=404 --tries=inf --wairetry=5

### delete=MsgId

The message with id MsgId is deleted. "DONE" is returned. This command never returns errors (even if the message MsgId does not exist).

### unique_id

This command returns a globally unique message id (which does not belong to any current or future message). The id is returned as a standard HTTP response body (see `download` above). All other parameters are ignored. Apart from the id itself, nothing else (e.g. "DONE") is returned.

Note that the "uniqueness" is only true during the single Pusher session (unless you use the `persistent` command line option, explained below).

### purge,[channel=ChannelId]

All messages in channel ChannelId (or channel "default", if omitted) are immediately discarded. "DONE" is returned.

#### Command line options

When starting Pusher, command line options are given e.g. as follows:

	pusher port=8000 persistent=/tmp/pusher.db

Options explanation:

### port=int

The port on which Pusher should run. If omitted, defaults to 8000.

### persistent=filename

By default, Pusher stores everything in memory. When it stops, all stored data is lost. If `persistent` is present, the database is written to a specified file and restored from it on restart.

The whole database is currently written to disk after each state change (i.e. after almost every type of request) which could take significant time if you have many megabytes of messages in your channels.

If you run several persistent Pusher instances concurrently on the same machine, make sure that each of them uses different database file!

### quit=yes_please

Pusher immediately quits.

## Some facts, caveats and possible future improvements

There is no security at all. Any client can connect to Pusher for any operation. However, *only clients from local machine* are allowed to connect. This is currently hardcoded.

Pusher is single-threaded. New request is buffered and handled after the previous finishes.

Pusher server does some very primitive logging to stdout.

The connections have 1 second hardcoded timeout. I.e. you must send your request (including the message data) sooner than 1 second after establishing connection.

Message size is unlimited and not checked. All channels and all messages are kept in memory until deleted.

Maximum channel size is hard-limited to 100 messages. If a channel already contains 100 messages, new incoming message is placed in the channel and the *oldest message is silently discarded*.

Argument validity checking is not optimal. Don't try weird stuff.

It's easy to use "single-use channels" if you want. E.g. "channel-537463-abc123", used for just one or two messages and then forgotten. You can use one "main" channel to send references to many "single-use" channels to different clients. The channels are created automatically when first used and deleted automatically when empty. They don't take any space if they are properly emptied.
