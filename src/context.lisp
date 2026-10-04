;;;; context.lisp — ZeroMQ contexts and library information

(in-package #:zmq5)

(defun version ()
  "Return the version of the loaded libzmq as three values:
major, minor and patch."
  (cffi:with-foreign-objects ((major :int) (minor :int) (patch :int))
    (%zmq-version major minor patch)
    (values (cffi:mem-ref major :int)
            (cffi:mem-ref minor :int)
            (cffi:mem-ref patch :int))))

(defun has-capability (capability)
  "Return true if libzmq was built with CAPABILITY, a string or keyword
such as :IPC, :PGM, :TIPC, :NORM, :CURVE, :GSSAPI or :DRAFT."
  (= 1 (%zmq-has (string-downcase (string capability)))))

(defstruct (context (:constructor %make-context (pointer))
                    (:predicate contextp)
                    (:copier nil))
  "A ZeroMQ context.  Contexts are thread safe and may be shared freely."
  (pointer nil))

(defmethod print-object ((context context) stream)
  (print-unreadable-object (context stream :type t :identity t)
    (unless (context-pointer context)
      (write-string "terminated" stream))))

(defun context-handle (context)
  (or (context-pointer context)
      (error "~S has been terminated." context)))

(defun make-context (&rest options &key &allow-other-keys)
  "Create a new ZeroMQ context.  OPTIONS is a property list of context
options, set as if by (SETF CONTEXT-OPTION), e.g. :IO-THREADS 2."
  (let ((pointer (%zmq-ctx-new)))
    (when (cffi:null-pointer-p pointer)
      (signal-zmq-error (%zmq-errno) "zmq_ctx_new"))
    (let ((context (%make-context pointer)))
      (handler-bind ((error (lambda (e)
                              (declare (ignore e))
                              (terminate-context context))))
        (loop for (name value) on options by #'cddr
              do (setf (context-option context name) value)))
      context)))

(defun terminate-context (context)
  "Terminate CONTEXT.  Blocking operations on its sockets in other
threads fail with ZMQ-TERMINATED.  This blocks until every socket of the
context has been closed and, depending on each socket's :LINGER option,
pending outgoing messages have been sent.  Calling it on a terminated
context does nothing."
  (let ((pointer (context-pointer context)))
    (when pointer
      (retrying-eintr "zmq_ctx_term" (%zmq-ctx-term pointer))
      (setf (context-pointer context) nil)))
  (values))

(defun shutdown-context (context)
  "Make all blocking operations on the sockets of CONTEXT fail with
ZMQ-TERMINATED, without terminating it.  Sockets must still be closed and
the context terminated with TERMINATE-CONTEXT."
  (check-rc "zmq_ctx_shutdown" (%zmq-ctx-shutdown (context-handle context)))
  (values))

(defun context-option (context name)
  "Return the value of context option NAME, a keyword such as
:IO-THREADS, :MAX-SOCKETS, :SOCKET-LIMIT, :MAX-MSGSZ, :IPV6 or :BLOCKY."
  (let ((value (check-rc "zmq_ctx_get"
                         (%zmq-ctx-get (context-handle context)
                                       (lookup name *context-options*
                                               "context option")))))
    (if (member name *boolean-context-options*)
        (/= value 0)
        value)))

(defun (setf context-option) (value context name)
  "Set context option NAME to VALUE, an integer or, for boolean options,
a generalised boolean."
  (check-rc "zmq_ctx_set"
            (%zmq-ctx-set (context-handle context)
                          (lookup name *context-options* "context option")
                          (cond ((integerp value) value)
                                (value 1)
                                (t 0))))
  value)

(defmacro with-context ((var &rest options) &body body)
  "Evaluate BODY with VAR bound to a new context created with OPTIONS.
The context is terminated when BODY exits, so every socket created in it
must be closed by then (WITH-SOCKET does that)."
  `(let ((,var (make-context ,@options)))
     (unwind-protect (progn ,@body)
       (terminate-context ,var))))
