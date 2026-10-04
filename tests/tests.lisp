;;;; tests.lisp — tests for zmq5
;;;;
;;;; A tiny self-contained harness, so the tests need nothing beyond zmq5.
;;;; Run with (asdf:test-system "zmq5") or `make test`.

(defpackage #:zmq5-tests
  (:use #:common-lisp)
  (:export #:run-tests))

(in-package #:zmq5-tests)

(defvar *tests* '())

(defmacro deftest (name &body body)
  `(progn
     (defun ,name () ,@body)
     (setf *tests* (append (remove ',name *tests*) (list ',name)))
     ',name))

(define-condition test-failure (error)
  ((form :initarg :form :reader test-failure-form))
  (:report (lambda (c s) (format s "Assertion failed: ~S" (test-failure-form c)))))

(defmacro is (form)
  `(unless ,form (error 'test-failure :form ',form)))

(defmacro signals (condition-type &body body)
  `(is (handler-case (progn ,@body nil)
         (,condition-type () t))))

(defun run-tests ()
  "Run every test, print a report and return true if all passed."
  (let ((failures 0))
    (dolist (test *tests*)
      (format t "~&~40A " test)
      (finish-output)
      (handler-case (progn (funcall test) (format t "ok~%"))
        (error (e)
          (incf failures)
          (format t "FAILED~%    ~A~%" e))))
    (format t "~&~D tests, ~D failures~%" (length *tests*) failures)
    (zerop failures)))

;;; helpers

(defun octets (&rest values)
  (make-array (length values) :element-type '(unsigned-byte 8)
                              :initial-contents values))

(defmacro with-pair ((a a-type b b-type &optional (endpoint "inproc://test"))
                     &body body)
  "Bind A, connect B to it, both with :LINGER 0 in a fresh context."
  (let ((ctx (gensym "CTX")) (ep (gensym "EP")))
    `(zmq5:with-context (,ctx)
       (zmq5:with-sockets ((,a ,ctx ,a-type :linger 0)
                           (,b ,ctx ,b-type :linger 0))
         (let ((,ep (zmq5:bind ,a ,endpoint)))
           (zmq5:connect ,b ,ep))
         ,@body))))

#+sbcl
(defun spawn (function) (sb-thread:make-thread function))
#+sbcl
(defun join (thread) (sb-thread:join-thread thread))

;;; library

(deftest version
  (multiple-value-bind (major minor patch) (zmq5:version)
    (is (= major 4))
    (is (integerp minor))
    (is (integerp patch))))

(deftest has-capability
  (is (zmq5:has-capability :ipc))
  (is (not (zmq5:has-capability "no-such-thing"))))

;;; contexts

(deftest context-options
  (zmq5:with-context (ctx :io-threads 2 :max-sockets 64)
    (is (= 2 (zmq5:context-option ctx :io-threads)))
    (is (= 64 (zmq5:context-option ctx :max-sockets)))
    (setf (zmq5:context-option ctx :ipv6) t)
    (is (eq t (zmq5:context-option ctx :ipv6)))))

(deftest terminate-twice
  (let ((ctx (zmq5:make-context)))
    (zmq5:terminate-context ctx)
    (zmq5:terminate-context ctx)
    (signals error (zmq5:make-socket ctx :req))))

;;; sockets and options

(deftest socket-options
  (zmq5:with-context (ctx)
    (zmq5:with-socket (s ctx :dealer :linger 0 :rcvhwm 42
                                     :routing-id "client-1")
      (is (eq :dealer (zmq5:socket-option s :type)))
      (is (= 0 (zmq5:socket-option s :linger)))
      (is (= 42 (zmq5:socket-option s :rcvhwm)))
      (is (equalp (babel:string-to-octets "client-1")
                  (zmq5:socket-option s :routing-id)))
      (setf (zmq5:socket-option s :maxmsgsize) (expt 2 40))
      (is (= (expt 2 40) (zmq5:socket-option s :maxmsgsize)))
      (setf (zmq5:socket-option s :immediate) t)
      (is (eq t (zmq5:socket-option s :immediate)))
      (is (eq :null (zmq5:socket-option s :mechanism)))
      (is (integerp (zmq5:socket-option s :fd)))
      (is (listp (zmq5:socket-option s :events))))))

(deftest unknown-option
  (zmq5:with-context (ctx)
    (zmq5:with-socket (s ctx :req :linger 0)
      (signals error (zmq5:socket-option s :no-such-option))
      (signals error (zmq5:make-socket ctx :no-such-type)))))

(deftest bind-ephemeral-port
  (zmq5:with-context (ctx)
    (zmq5:with-socket (s ctx :pull :linger 0)
      (let ((endpoint (zmq5:bind s "tcp://127.0.0.1:*")))
        (is (search "tcp://127.0.0.1:" endpoint))
        (is (string= endpoint (zmq5:socket-option s :last-endpoint)))
        (zmq5:unbind s endpoint)))))

(deftest bad-endpoint
  (zmq5:with-context (ctx)
    (zmq5:with-socket (s ctx :pull :linger 0)
      (let ((condition (handler-case (zmq5:bind s "bogus://x")
                         (zmq5:zmq-error (e) e))))
        (is (typep condition 'zmq5:zmq-error))
        (is (eq :eprotonosupport (zmq5:zmq-error-name condition)))
        (is (string= "zmq_bind" (zmq5:zmq-error-function condition)))
        (is (plusp (length (princ-to-string condition))))))))

(deftest close-twice
  (zmq5:with-context (ctx)
    (let ((s (zmq5:make-socket ctx :req)))
      (zmq5:close-socket s :linger 0)
      (zmq5:close-socket s)
      (signals error (zmq5:connect s "inproc://x")))))

;;; messaging

(deftest req-rep
  (with-pair (rep :rep req :req)
    (zmq5:send req "hello")
    (is (string= "hello" (zmq5:recv-string rep)))
    (zmq5:send rep (octets 1 2 3))
    (multiple-value-bind (data more) (zmq5:recv req)
      (is (equalp data (octets 1 2 3)))
      (is (typep data '(simple-array (unsigned-byte 8) (*))))
      (is (not more)))))

(deftest push-pull-tcp
  (with-pair (pull :pull push :push "tcp://127.0.0.1:*")
    (dotimes (i 100)
      (zmq5:send push (format nil "msg ~D" i)))
    (dotimes (i 100)
      (is (string= (format nil "msg ~D" i) (zmq5:recv-string pull))))))

(deftest empty-and-unicode
  (with-pair (pull :pull push :push)
    (zmq5:send push nil)
    (zmq5:send push "")
    (zmq5:send push "λ ∀ ☃ ü")
    (is (equalp (octets) (zmq5:recv pull)))
    (is (string= "" (zmq5:recv-string pull)))
    (is (string= "λ ∀ ☃ ü" (zmq5:recv-string pull)))))

(deftest non-simple-vector
  (with-pair (pull :pull push :push)
    (let ((v (make-array 3 :adjustable t :fill-pointer 3
                           :initial-contents '(7 8 9))))
      (zmq5:send push v)
      (zmq5:send push #(1 2 3))
      (is (equalp (octets 7 8 9) (zmq5:recv pull)))
      (is (equalp (octets 1 2 3) (zmq5:recv pull))))))

(deftest large-message
  (with-pair (pull :pull push :push "tcp://127.0.0.1:*")
    (let ((data (make-array (* 4 1024 1024) :element-type '(unsigned-byte 8))))
      (dotimes (i (length data)) (setf (aref data i) (mod (* i 7) 256)))
      (is (= (length data) (zmq5:send push data)))
      (is (equalp data (zmq5:recv pull))))))

(deftest multipart
  (with-pair (pull :pull push :push)
    (zmq5:send-multipart push (list "a" (octets 1) nil "d"))
    (zmq5:send push "single")
    (let ((parts (zmq5:recv-multipart pull)))
      (is (= 4 (length parts)))
      (is (equalp (octets 97) (first parts)))
      (is (equalp (octets) (third parts))))
    (is (equal '("single") (zmq5:recv-multipart pull :as :string)))))

(deftest router-dealer
  (with-pair (router :router dealer :dealer)
    (setf (zmq5:socket-option dealer :routing-id) "D1")
    (zmq5:disconnect dealer "inproc://test")
    (zmq5:connect dealer "inproc://test")
    (zmq5:send dealer "ping")
    (destructuring-bind (id body) (zmq5:recv-multipart router)
      (is (equalp (babel:string-to-octets "D1") id))
      (is (equalp (babel:string-to-octets "ping") body))
      (zmq5:send-multipart router (list id "pong")))
    (is (string= "pong" (zmq5:recv-string dealer)))))

(deftest pub-sub
  (with-pair (pub :pub sub :sub)
    (zmq5:subscribe sub "weather")
    ;; Subscriptions propagate asynchronously; send until one arrives.
    (loop repeat 100
          do (zmq5:send pub "news nothing")
             (zmq5:send pub "weather sunny")
          until (zmq5:poll (list (list sub :pollin)) :timeout 10))
    (is (string= "weather sunny" (zmq5:recv-string sub)))
    (zmq5:unsubscribe sub "weather")))

(deftest dontwait-signals-again
  (with-pair (pull :pull push :push)
    (signals zmq5:zmq-again (zmq5:recv pull :dontwait t))
    (let ((condition (handler-case (zmq5:recv pull :dontwait t)
                       (zmq5:zmq-again (e) e))))
      (is (eq :eagain (zmq5:zmq-error-name condition))))))

(deftest rcvtimeo-signals-again
  (with-pair (pull :pull push :push)
    (setf (zmq5:socket-option pull :rcvtimeo) 20)
    (signals zmq5:zmq-again (zmq5:recv pull))))

(deftest req-state-machine
  (with-pair (rep :rep req :req)
    (zmq5:send req "one")
    (let ((condition (handler-case (zmq5:send req "two")
                       (zmq5:zmq-error (e) e))))
      (is (eq :efsm (zmq5:zmq-error-name condition))))))

;;; polling

(deftest poll-timeout
  (with-pair (pull :pull push :push)
    (let ((start (get-internal-real-time)))
      (multiple-value-bind (events count)
          (zmq5:poll (list (list pull :pollin)) :timeout 50)
        (is (equal '(nil) events))
        (is (= 0 count)))
      (is (>= (- (get-internal-real-time) start)
              (* 0.04 internal-time-units-per-second))))))

(deftest poll-ready
  (with-pair (pull :pull push :push)
    (zmq5:send push "x")
    (multiple-value-bind (events count)
        (zmq5:poll (list (list pull :pollin) (list push :pollout)))
      (is (= 2 count))
      (is (equal '((:pollin) (:pollout)) events)))
    (is (equal '(nil) (zmq5:poll (list (list push :pollin)) :timeout 0)))))

;;; security helpers

(deftest z85
  ;; The test vector from the Z85 specification (ZeroMQ RFC 32).
  (let ((data (octets #x86 #x4F #xD2 #x6F #xB5 #x59 #xF7 #x5B)))
    (is (string= "HelloWorld" (zmq5:z85-encode data)))
    (is (equalp data (zmq5:z85-decode "HelloWorld")))
    (signals error (zmq5:z85-encode (octets 1 2 3)))
    (signals error (zmq5:z85-decode "abc"))))

(deftest curve
  (when (zmq5:has-capability :curve)
    (multiple-value-bind (server-public server-secret) (zmq5:curve-keypair)
      (is (= 40 (length server-public)))
      (is (string= server-public (zmq5:curve-public server-secret)))
      (multiple-value-bind (client-public client-secret) (zmq5:curve-keypair)
        (zmq5:with-context (ctx)
          (zmq5:with-sockets ((server ctx :rep :linger 0
                                      :curve-server t
                                      :curve-secretkey server-secret)
                              (client ctx :req :linger 0
                                      :curve-serverkey server-public
                                      :curve-publickey client-public
                                      :curve-secretkey (zmq5:z85-decode
                                                        client-secret)))
            (is (eq :curve (zmq5:socket-option server :mechanism)))
            (is (string= server-public
                         (zmq5:socket-option client :curve-serverkey)))
            (zmq5:connect client (zmq5:bind server "tcp://127.0.0.1:*"))
            (zmq5:send client "secret")
            (is (string= "secret" (zmq5:recv-string server)))))))))

;;; monitoring

(deftest monitor
  (zmq5:with-context (ctx)
    (zmq5:with-sockets ((s ctx :rep :linger 0)
                        (mon ctx :pair :linger 0))
      (zmq5:monitor s "inproc://monitor" :events '(:listening :accepted))
      (zmq5:connect mon "inproc://monitor")
      (let ((endpoint (zmq5:bind s "tcp://127.0.0.1:*")))
        (multiple-value-bind (event value address) (zmq5:recv-monitor-event mon)
          (is (eq :listening event))
          (is (integerp value))
          (is (string= endpoint address))))
      (zmq5:monitor s nil))))

;;; threads

#+sbcl
(deftest gc-during-blocking-recv
  ;; SBCL stops threads for GC with signals, interrupting the blocking
  ;; zmq_msg_recv with EINTR, which must be retried transparently.
  (with-pair (pull :pull push :push)
    (let ((thread (spawn (lambda () (zmq5:recv-string pull)))))
      (dotimes (i 5) (sb-ext:gc :full t) (sleep 0.01))
      (zmq5:send push "after gc")
      (is (string= "after gc" (join thread))))))

#+sbcl
(deftest shutdown-unblocks-recv
  (zmq5:with-context (ctx)
    (zmq5:with-socket (pull ctx :pull :linger 0)
      (zmq5:bind pull "inproc://shutdown")
      (let ((thread (spawn (lambda ()
                             (handler-case (zmq5:recv pull)
                               (zmq5:zmq-terminated () :terminated))))))
        (sleep 0.05)
        (zmq5:shutdown-context ctx)
        (is (eq :terminated (join thread)))))))

#+sbcl
(deftest steerable-proxy
  (zmq5:with-context (ctx)
    (zmq5:with-sockets ((front ctx :pull :linger 0)
                        (back ctx :push :linger 0)
                        (control ctx :pair :linger 0)
                        (in ctx :push :linger 0)
                        (out ctx :pull :linger 0)
                        (command ctx :pair :linger 0))
      (zmq5:bind front "inproc://front")
      (zmq5:bind back "inproc://back")
      (zmq5:bind control "inproc://control")
      (zmq5:connect in "inproc://front")
      (zmq5:connect out "inproc://back")
      (zmq5:connect command "inproc://control")
      (let ((thread (spawn (lambda ()
                             (zmq5:proxy-steerable front back control)))))
        (zmq5:send in "through the proxy")
        (is (string= "through the proxy" (zmq5:recv-string out)))
        (zmq5:send command "TERMINATE")
        (is (eq t (join thread)))))))
