;;;; hello.lisp — the classic ZeroMQ request/reply "Hello World"
;;;;
;;;; In one REPL:     (zmq5-examples:hello-server)
;;;; In another:      (zmq5-examples:hello-client)

(defpackage #:zmq5-examples
  (:use #:common-lisp)
  (:export #:hello-server #:hello-client
           #:weather-server #:weather-client))

(in-package #:zmq5-examples)

(defun hello-server (&key (endpoint "tcp://*:5555"))
  "Answer every request with \"World\", forever."
  (zmq5:with-context (ctx)
    (zmq5:with-socket (socket ctx :rep)
      (zmq5:bind socket endpoint)
      (loop
        (format t "Received ~A~%" (zmq5:recv-string socket))
        (sleep 1)                       ; do some "work"
        (zmq5:send socket "World")))))

(defun hello-client (&key (endpoint "tcp://localhost:5555") (count 10))
  "Send COUNT requests and print the replies."
  (zmq5:with-context (ctx)
    (zmq5:with-socket (socket ctx :req :linger 0)
      (zmq5:connect socket endpoint)
      (dotimes (i count)
        (zmq5:send socket "Hello")
        (format t "Reply ~D: ~A~%" i (zmq5:recv-string socket))))))
