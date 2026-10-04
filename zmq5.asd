;;;; zmq5.asd

(defsystem "zmq5"
  :description "Common Lisp bindings to ZeroMQ (libzmq 4.x, libzmq.so.5)"
  :version "0.1.0"
  :license "MIT"
  :depends-on ("cffi" "babel")
  :pathname "src/"
  :serial t
  :components ((:file "package")
               (:file "ffi")
               (:file "constants")
               (:file "errors")
               (:file "util")
               (:file "context")
               (:file "socket")
               (:file "transfer")
               (:file "poll")
               (:file "extras"))
  :in-order-to ((test-op (test-op "zmq5/tests"))))

(defsystem "zmq5/tests"
  :description "Tests for zmq5"
  :license "MIT"
  :depends-on ("zmq5")
  :pathname "tests/"
  :components ((:file "tests"))
  :perform (test-op (o c)
             (unless (uiop:symbol-call '#:zmq5-tests '#:run-tests)
               (error "zmq5 tests failed."))))
