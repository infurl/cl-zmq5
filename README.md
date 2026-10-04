# zmq5 — ZeroMQ for Common Lisp

Common Lisp bindings to [ZeroMQ](https://zeromq.org/) through
`libzmq.so.5`, the shared library of libzmq 4.x.

* **One dependency:** [CFFI](https://cffi.common-lisp.dev/) (and
  babel, which CFFI already uses). Both are in Quicklisp and in Debian
  (`cl-cffi`).
* **No C compiler needed:** there is no groveller and no C glue. The
  constants are taken from the stable libzmq 4.x ABI.
* **Lisp-friendly:** keywords instead of `ZMQ_*` constants, octet
  vectors and strings instead of raw buffers, conditions instead of
  return codes, `with-` macros for cleanup.
* **Safe under SBCL's signals:** blocking calls interrupted by `EINTR`
  are retried. SBCL stops threads for GC with signals, which interrupts
  blocking calls.

## Installation

You need the libzmq runtime library. On Debian or Ubuntu:

```sh
sudo apt install libzmq5       # runtime library; the headers are not needed
sudo apt install sbcl cl-cffi  # or get cffi from Quicklisp
```

Put this directory where ASDF can find it, for example
`~/common-lisp/cl-zmq5` or `~/quicklisp/local-projects/cl-zmq5`, then:

```lisp
(asdf:load-system "zmq5")      ; or (ql:quickload "zmq5")
```

Run the tests with `make test` or `(asdf:test-system "zmq5")`.

## Example

```lisp
;; Server
(zmq5:with-context (ctx)
  (zmq5:with-socket (socket ctx :rep)
    (zmq5:bind socket "tcp://*:5555")
    (loop
      (format t "Received ~A~%" (zmq5:recv-string socket))
      (zmq5:send socket "World"))))

;; Client
(zmq5:with-context (ctx)
  (zmq5:with-socket (socket ctx :req :linger 0)
    (zmq5:connect socket "tcp://localhost:5555")
    (zmq5:send socket "Hello")
    (zmq5:recv-string socket)))
```

More examples are in `examples/`.

## API

### Contexts

| Function | Description |
|---|---|
| `(make-context &rest options)` | New context. Options are a plist such as `:io-threads 2`. |
| `(terminate-context ctx)` | Terminates the context. Blocks until all its sockets are closed. |
| `(shutdown-context ctx)` | Makes blocking calls on the context's sockets fail with `zmq-terminated`. |
| `(context-option ctx name)`, `setf` | `:io-threads :max-sockets :socket-limit :thread-priority :thread-sched-policy :max-msgsz :msg-t-size :ipv6 :blocky` … |
| `(with-context (var &rest options) &body)` | Creates a context and terminates it on exit. |

### Sockets

| Function | Description |
|---|---|
| `(make-socket ctx type &rest options)` | `type` is one of `:pair :pub :sub :req :rep :dealer :router :pull :push :xpub :xsub :stream`. Options are applied in order. |
| `(close-socket socket &key linger)` | Closes the socket. Closing it again does nothing. |
| `(with-socket (var ctx type &rest options) &body)` | Creates a socket and closes it on exit. |
| `(with-sockets ((var ctx type . options) ...) &body)` | Several `with-socket` forms at once. |
| `(bind socket endpoint)` | Binds and returns the endpoint actually bound, so `"tcp://127.0.0.1:*"` gives you the port. |
| `(unbind socket endpoint)`, `(connect …)`, `(disconnect …)` | As in libzmq. |
| `(subscribe socket &optional prefix)`, `(unsubscribe …)` | For `:sub` sockets. The default prefix `""` matches every message. |
| `(socket-option socket name)`, `setf` | Every stable `ZMQ_*` option, named as a keyword: `ZMQ_RCVHWM` becomes `:rcvhwm`. |

Option values are converted between Lisp and C types:

* Integer options are integers.
* Flag options are `T`/`NIL`.
* Binary options (`:routing-id`, `:subscribe`) are octet vectors when you
  read them, and accept strings or octet vectors when you set them.
* Text options are strings.
* CURVE keys accept a 40-character Z85 string or 32 raw octets, and read
  back as Z85.
* `:type`, `:mechanism` and `:events` read back as keywords.

### Messages

| Function | Description |
|---|---|
| `(send socket data &key more dontwait encoding)` | `data` is an octet vector, a string (UTF-8 by default) or `nil` (an empty part). |
| `(send-multipart socket parts &key dontwait encoding)` | Sends a list of parts as one message. |
| `(recv socket &key dontwait as encoding)` | Returns `(values data more-p)`. `as` is `:octets` (default) or `:string`. |
| `(recv-string socket &key dontwait encoding)` | Same as `recv` with `:as :string`. |
| `(recv-multipart socket &key dontwait as encoding)` | Returns every part of the next message as a list. |

Messages of any size can be received. Each receive goes through a
`zmq_msg_t`, so there is no fixed buffer.

### Polling

```lisp
(zmq5:poll (list (list frontend :pollin)
                 (list backend :pollin :pollout)
                 (list some-fd :pollin))   ; plain file descriptors work too
           :timeout 1000)                  ; milliseconds; NIL waits forever
;; => ((:pollin) NIL (:pollin)), 2
```

### Proxies, monitoring and security

| Function | Description |
|---|---|
| `(proxy frontend backend &optional capture)` | Runs `zmq_proxy` until the context is terminated. |
| `(proxy-steerable frontend backend control &optional capture)` | Can be paused, resumed and stopped with `"PAUSE"`, `"RESUME"` and `"TERMINATE"` sent to `control`. |
| `(monitor socket "inproc://mon" &key events)` | Publishes socket events. Read them with `recv-monitor-event` from a `:pair` socket. |
| `(recv-monitor-event pair-socket &key dontwait)` | Returns `(values event value endpoint)`, e.g. `:listening 12 "tcp://…"`. |
| `(curve-keypair)` | Returns `(values public secret)` as Z85 strings. |
| `(curve-public secret)` | Derives the public key from a secret key. |
| `(z85-encode octets)`, `(z85-decode string)` | Z85 encoding and decoding. |
| `(version)` | Returns `(values major minor patch)`. |
| `(has-capability :curve)` | Checks for a capability: `:ipc :pgm :tipc :norm :curve :gssapi :draft`. |

### Errors

Failures signal `zmq-error`. `zmq-error-errno` gives the error number,
`zmq-error-name` gives it as a keyword such as `:einval`, `:efsm` or
`:eprotonosupport`, and `zmq-error-function` names the libzmq function
that failed. Two subclasses are worth handling specifically:

* `zmq-again`: the operation would block (`:dontwait`) or timed out
  (`:rcvtimeo` / `:sndtimeo`).
* `zmq-terminated`: the socket's context was terminated or shut down.

## Things to know

* **Sockets are not thread-safe.** Use each socket from one thread at a
  time. Contexts can be shared between threads.
* **Linger.** libzmq's default `:linger` is -1. That means
  `terminate-context` waits forever for unsent messages to be delivered.
  Pass `:linger 0` when you create a socket, or call
  `(close-socket s :linger 0)`, if you would rather drop them.
* **Stopping a blocked thread.** Call `shutdown-context` or
  `terminate-context` from another thread. The blocked `recv` then
  signals `zmq-terminated`.
* **DRAFT APIs** of libzmq (`:server`, `:client`, `:radio`, `:dish`,
  `zmq_poller`, …) are not bound, because distribution builds of libzmq
  usually don't include them. Integer socket types are passed through
  if you need one.

## License

MIT; see `LICENSE`.
