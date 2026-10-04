;;;; socket.lisp — ZeroMQ sockets, options and endpoints

(in-package #:zmq5)

(defstruct (socket (:constructor %make-socket (pointer context type))
                   (:predicate socketp)
                   (:copier nil))
  "A ZeroMQ socket.  Sockets are NOT thread safe: use each one from a
single thread at a time."
  (pointer nil)
  (context nil :read-only t)
  (type nil :read-only t))

(defmethod print-object ((socket socket) stream)
  (print-unreadable-object (socket stream :type t :identity t)
    (format stream "~S~:[ closed~;~]"
            (socket-type socket) (socket-pointer socket))))

(defun socket-handle (socket)
  (or (socket-pointer socket)
      (error "~S has been closed." socket)))

(defun make-socket (context type &rest options &key &allow-other-keys)
  "Create a socket of TYPE in CONTEXT.  TYPE is one of :PAIR :PUB :SUB
:REQ :REP :DEALER :ROUTER :PULL :PUSH :XPUB :XSUB :STREAM, or an integer.
OPTIONS is a property list of socket options, set in order as if by
(SETF SOCKET-OPTION), e.g. :LINGER 0 :SUBSCRIBE \"\"."
  (let ((pointer (%zmq-socket (context-handle context)
                              (lookup type *socket-types* "socket type"))))
    (when (cffi:null-pointer-p pointer)
      (signal-zmq-error (%zmq-errno) "zmq_socket"))
    (let ((socket (%make-socket pointer context type)))
      (handler-bind ((error (lambda (e)
                              (declare (ignore e))
                              (close-socket socket))))
        (loop for (name value) on options by #'cddr
              do (setf (socket-option socket name) value)))
      socket)))

(defun close-socket (socket &key linger)
  "Close SOCKET.  If LINGER is given it sets the :LINGER option first
(in milliseconds; 0 discards unsent messages, -1 waits forever).
Closing a closed socket does nothing."
  (let ((pointer (socket-pointer socket)))
    (when pointer
      (when linger
        (setf (socket-option socket :linger) linger))
      (setf (socket-pointer socket) nil)
      (check-rc "zmq_close" (%zmq-close pointer))))
  (values))

(defmacro with-socket ((var context type &rest options) &body body)
  "Evaluate BODY with VAR bound to a new socket, closed when BODY exits.
See MAKE-SOCKET for TYPE and OPTIONS."
  `(let ((,var (make-socket ,context ,type ,@options)))
     (unwind-protect (progn ,@body)
       (close-socket ,var))))

(defmacro with-sockets (bindings &body body)
  "Like nested WITH-SOCKET forms: each binding is (VAR CONTEXT TYPE . OPTIONS)."
  (if (null bindings)
      `(progn ,@body)
      `(with-socket ,(first bindings)
         (with-sockets ,(rest bindings) ,@body))))

;;; Options

(defconstant +option-buffer-size+ 1024
  "Big enough for any variable-length option: routing ids are at most
255 octets and endpoints are bounded by the length of a file name.")

(defconstant +z85-key-length+ 40)

(defun get-fixed-option (handle code ctype)
  (cffi:with-foreign-objects ((value ctype) (size :size))
    (setf (cffi:mem-ref size :size) (cffi:foreign-type-size ctype))
    (check-rc "zmq_getsockopt" (%zmq-getsockopt handle code value size))
    (cffi:mem-ref value ctype)))

(defun get-buffer-option (handle code buffer-size)
  "Return the octets of a variable-length option."
  (cffi:with-foreign-objects ((value :uint8 buffer-size) (size :size))
    (setf (cffi:mem-ref size :size) buffer-size)
    (check-rc "zmq_getsockopt" (%zmq-getsockopt handle code value size))
    (foreign-to-octets value (cffi:mem-ref size :size))))

(defun strip-nul (octets)
  (let ((end (position 0 octets)))
    (if end (subseq octets 0 end) octets)))

(defun socket-option (socket name)
  "Return the value of socket option NAME, a keyword named after the
ZMQ_ constant (e.g. :LINGER for ZMQ_LINGER, :LAST-ENDPOINT, :RCVMORE).
Integers are returned as integers, flags as booleans, binary data as
octet vectors and text (including CURVE keys, in Z85) as strings.
:TYPE, :MECHANISM and :EVENTS are returned as keywords."
  (let ((handle (socket-handle socket)))
    (multiple-value-bind (code type) (socket-option-info name)
      (let ((value
              (ecase type
                (:int (get-fixed-option handle code :int))
                (:boolean (/= 0 (get-fixed-option handle code :int)))
                (:int64 (get-fixed-option handle code :int64))
                (:uint64 (get-fixed-option handle code :uint64))
                (:bytes (get-buffer-option handle code +option-buffer-size+))
                (:string (decode (strip-nul (get-buffer-option
                                             handle code +option-buffer-size+))
                                 :utf-8))
                (:key (decode (strip-nul (get-buffer-option
                                          handle code (1+ +z85-key-length+)))
                              :ascii)))))
        (case name
          (:type (reverse-lookup value *socket-types*))
          (:mechanism (reverse-lookup value *mechanisms*))
          (:events (int-to-events value *poll-events*))
          (t value))))))

(defun set-fixed-option (handle code ctype value)
  (cffi:with-foreign-object (pointer ctype)
    (setf (cffi:mem-ref pointer ctype) value)
    (check-rc "zmq_setsockopt"
              (%zmq-setsockopt handle code pointer
                               (cffi:foreign-type-size ctype)))))

(defun set-buffer-option (handle code data)
  (if (null data)
      (check-rc "zmq_setsockopt"
                (%zmq-setsockopt handle code (cffi:null-pointer) 0))
      (with-octets (pointer length data)
        (check-rc "zmq_setsockopt"
                  (%zmq-setsockopt handle code pointer length)))))

(defun key-octets (key)
  "A CURVE key as libzmq wants it: 32 raw octets, or a Z85 string
followed by a NUL."
  (if (stringp key)
      (progn
        (unless (= (length key) +z85-key-length+)
          (error "A Z85 CURVE key must be ~D characters long, not ~D: ~S"
                 +z85-key-length+ (length key) key))
        (let ((octets (make-octets (1+ +z85-key-length+))))
          (replace octets (babel:string-to-octets key :encoding :ascii))
          (setf (aref octets +z85-key-length+) 0)
          octets))
      (let ((octets (to-octets key)))
        (unless (= (length octets) 32)
          (error "A binary CURVE key must be 32 octets long, not ~D."
                 (length octets)))
        octets)))

(defun (setf socket-option) (value socket name)
  "Set socket option NAME to VALUE.  See SOCKET-OPTION for names.
Binary options accept octet vectors or strings (encoded as UTF-8);
boolean options accept any generalised boolean."
  (let ((handle (socket-handle socket)))
    (multiple-value-bind (code type) (socket-option-info name)
      (ecase type
        (:int (set-fixed-option handle code :int value))
        (:boolean (set-fixed-option handle code :int
                                    (cond ((integerp value) value)
                                          (value 1)
                                          (t 0))))
        (:int64 (set-fixed-option handle code :int64 value))
        (:uint64 (set-fixed-option handle code :uint64 value))
        ((:bytes :string) (set-buffer-option handle code value))
        (:key (set-buffer-option handle code (key-octets value))))))
  value)

;;; Endpoints

(defun bind (socket endpoint)
  "Bind SOCKET to ENDPOINT, e.g. \"tcp://*:5555\" or \"inproc://name\".
Return the endpoint actually bound, which differs from ENDPOINT when it
asks for an ephemeral port as in \"tcp://127.0.0.1:*\"."
  (check-rc "zmq_bind" (%zmq-bind (socket-handle socket) endpoint))
  (socket-option socket :last-endpoint))

(defun unbind (socket endpoint)
  "Stop accepting connections on ENDPOINT, as returned by BIND."
  (check-rc "zmq_unbind" (%zmq-unbind (socket-handle socket) endpoint))
  (values))

(defun connect (socket endpoint)
  "Connect SOCKET to ENDPOINT, e.g. \"tcp://localhost:5555\".  The
connection is made asynchronously; this returns immediately."
  (check-rc "zmq_connect" (%zmq-connect (socket-handle socket) endpoint))
  (values))

(defun disconnect (socket endpoint)
  "Disconnect SOCKET from ENDPOINT."
  (check-rc "zmq_disconnect"
            (%zmq-disconnect (socket-handle socket) endpoint))
  (values))

(defun subscribe (socket &optional (prefix ""))
  "Subscribe a :SUB socket to messages starting with PREFIX (a string
or octet vector).  The default, \"\", subscribes to everything."
  (setf (socket-option socket :subscribe) prefix)
  (values))

(defun unsubscribe (socket &optional (prefix ""))
  "Remove a subscription made by SUBSCRIBE."
  (setf (socket-option socket :unsubscribe) prefix)
  (values))
