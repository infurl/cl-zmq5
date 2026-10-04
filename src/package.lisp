;;;; package.lisp — package definition for ZMQ5, a CFFI binding to libzmq 4.x

(defpackage #:zmq5
  (:use #:common-lisp)
  (:export
   ;; library
   #:version
   #:has-capability
   ;; conditions
   #:zmq-error
   #:zmq-error-errno
   #:zmq-error-name
   #:zmq-error-function
   #:zmq-again
   #:zmq-terminated
   ;; contexts
   #:context
   #:contextp
   #:make-context
   #:terminate-context
   #:shutdown-context
   #:context-option
   #:with-context
   ;; sockets
   #:socket
   #:socketp
   #:socket-context
   #:socket-type
   #:make-socket
   #:close-socket
   #:with-socket
   #:with-sockets
   #:socket-option
   #:bind
   #:unbind
   #:connect
   #:disconnect
   #:subscribe
   #:unsubscribe
   ;; sending and receiving
   #:send
   #:send-multipart
   #:recv
   #:recv-string
   #:recv-multipart
   ;; polling
   #:poll
   ;; proxies
   #:proxy
   #:proxy-steerable
   ;; monitoring
   #:monitor
   #:recv-monitor-event
   ;; security helpers
   #:z85-encode
   #:z85-decode
   #:curve-keypair
   #:curve-public))
