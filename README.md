# Pusher

Very simple IPC queue accessed using unix domain sockets. Written in pure LuaJIT + LuaSocket (uses no other libraries). Partly inspired by [beanstalkd](https://beanstalkd.github.io/) and [mosquitto](http://www.mosquitto.org/).

## Basic concepts

Pusher runs as a server on a chosen unix domain socket. Pusher can manage any number of channels. Each channel is identified by alphanumeric string. Each chanel acts as a queue (FIFO) of messages. A message can be anything. It's just a sequence of bytes, Pusher doesn't care what it represents. Each message has globally unique id which is used for deleting it. A message cannot be empty.

Application X pushes message into channel. Application Y gets the message from the channel, handles it and - if the handling is succesful - deletes it from the channel. Deleting can also happen automatically when geting the message.

## Interface

The request and its parameters are sent to Pusher as a single line, separated using the "|" character. For example this single-line command:

	push|channel=MyChannel|message=Hello, world|no_id

This pushes the message 'Hello, world' (12 bytes) to channel 'MyChannel'. The response (best parsed as lines) will be a single line with the string "DONE". There is an alternative way to send long / non-ASCII messages, explained below.

"DONE" final line always indicates succesful completion of the operation.

When returned instead of "DONE", the line "ERROR: <ErrorMessage>" indicates that something went wrong.

Lines are separated by "\n" character.

Note that the order of parameters does not matter. The example above is exactly equal to:

	channel=MyChannel|no_id|message=Hello, world|push

## Commands and parameters:

### push,[channel=ChannelId,][message=MessageData,][no_id,]

Pushes a message with content MessageData to channel ChannelId and returns its assigned id. If `channel` is omitted, channel named "default" is assumed. Channel ids are alphanumeric, including the "-" character. They are case-sensitive.

If `no_id` is present, the id is not returned (only "DONE").

If `message` parameter is omitted (because the message is too long for URL or contains weird non-printable data or the character "|"), the request line must be followed by the length of the message (as a number on a separate line) and then by the raw body of the message.

That means this one-line request:

	push|channel=MyChannel|message=Hello, world|no_id

is exactly equal to this three-line request:

	push|channel=MyChannel|no_id
	12
	Hello, world

### get,[channel=ChannelId,][no_id,][no_age,][all,][autodelete,]

Returns the first message from channel ChannelId. The message is *not automatically deleted* (by default) and must be deleted using `delete` command or using `autodelete` option for `get` command. The typical succesful response to `get` may look as follows (the message is "HelloWorld", its length is 10 bytes, its id is "abc123" and age is 600 seconds):

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

I.e. first the string "MESSAGE", then the length of the message (in bytes), then CRLF, then the raw message data, then the string "ID", the message id, then the string "AGE", then the age of the message (in seconds), and finally "DONE"

*Very important:* If the message contains the "\n" newline character (or any non-sanitized binary data) you MUST read its body using `client:receive(messageLength)` (not using `client:receive("*l")`) and you also MUST manually skip the "\n" character that follows the message body. Only if you are absolutely sure that message is clean string without line breaks, you can ignore the returned length and read the message using the plain `client:receive("*l)` (or `client:receive()`).

If there are no messages in the channel, only "DONE" is returned.

If `all` option is present, all messages in the relevant queue are returned (from oldest to newest, each with its ID and AGE). "DONE" is output only once, after the last message.

If `autodelete` is present, all retrieved messages are automatically deleted from the channel.

If `no_id` is present, no message ids are returned.

If `no_age` is present, no message ages are returned.

### delete=MsgId

The message with id MsgId is deleted. "DONE" is returned. This command never returns errors (even if the message MsgId does not exist).

### unique_id

This command returns the string "ID", followed by a globally unique message id string (which does not belong to any current or future message).

Note that the "uniqueness" is only true during the single Pusher session (unless you use the `persistent` command line option, explained below).

### purge,[channel=ChannelId]

All messages in channel ChannelId (or channel "default", if omitted) are immediately discarded. "DONE" is returned.

#### Command line options

When starting Pusher, command line options are given e.g. as follows:

	pusher port=8000 persistent=/tmp/pusher.db

Options explanation:

### socket=filename

The socket on which Pusher listens to requests. If omitted, defaults to `/tmp/pusher_socket`.

### persistent=filename

By default, Pusher stores everything in memory. When it stops, all stored data is lost. If `persistent` is present, the database is written to a specified file and restored from it on restart.

The whole database is currently written to disk after each state change (i.e. after almost every type of request) which could take significant time if you have many megabytes of messages in your channels.

If you run several persistent Pusher instances concurrently on the same machine, make sure that each of them uses different database file!

### quit=yes_please

Pusher immediately quits.

### reset=yes_please

Clears everything in database, including the unique id counter (effectively a hard restart).

## Some facts, caveats and possible future improvements

There is no security at all. Any client (that has access to the socket file) can connect to Pusher for any operation.

Pusher is single-threaded. New request is buffered and handled after the previous finishes.

Pusher server does some very primitive logging to stdout.

The connections have 1 second hardcoded timeout. I.e. you must send your request (including the message data) sooner than 1 second after establishing connection.

Message size is unlimited and not checked. All channels and all messages are kept in memory until deleted.

Maximum channel size is hard-limited to 100 messages. If a channel already contains 100 messages, new incoming message is placed in the channel and the *oldest message is silently discarded*.

Argument validity checking is not optimal. Don't try weird stuff.

It's easy to use "single-use channels" if you want. E.g. "channel-537463-abc123", used for just one or two messages and then forgotten. You can use one "main" channel to send references to many "single-use" channels to different clients. The channels are created automatically when first used and deleted automatically when empty. They don't take any space if they are properly emptied.
