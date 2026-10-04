;;;; ffi.lisp — raw foreign bindings to libzmq
;;;;
;;;; Everything here is internal.  Functions are named %ZMQ-... and map
;;;; one-to-one onto the C API in zmq.h.  Only the stable (non-DRAFT) API
;;;; of libzmq 4.x is bound, which is what the libzmq.so.5 SONAME provides.

(in-package #:zmq5)

(cffi:define-foreign-library libzmq
  (:darwin (:or "libzmq.5.dylib" "libzmq.dylib"))
  (:unix (:or "libzmq.so.5" "libzmq.so"))
  (:windows (:or "libzmq.dll" "libzmq-mt-4_3_5.dll"))
  (t (:default "libzmq")))

(cffi:use-foreign-library libzmq)

;;; zmq_msg_t is an opaque 64-byte, pointer-aligned structure.  We
;;; allocate it as eight 64-bit words to get the alignment for free.
(defconstant +msg-words+ 8)

(defmacro with-msg ((var) &body body)
  "Bind VAR to a stack-allocated, uninitialised zmq_msg_t."
  `(cffi:with-foreign-object (,var :uint64 +msg-words+)
     ,@body))

(cffi:defcstruct (pollitem :conc-name pollitem-)
  (socket :pointer)
  (fd :int)                             ; zmq_fd_t is int on POSIX
  (events :short)
  (revents :short))

;;; errors and version

(cffi:defcfun ("zmq_errno" %zmq-errno) :int)
(cffi:defcfun ("zmq_strerror" %zmq-strerror) :string (errnum :int))
(cffi:defcfun ("zmq_version" %zmq-version) :void
  (major (:pointer :int)) (minor (:pointer :int)) (patch (:pointer :int)))
(cffi:defcfun ("zmq_has" %zmq-has) :int (capability :string))

;;; contexts

(cffi:defcfun ("zmq_ctx_new" %zmq-ctx-new) :pointer)
(cffi:defcfun ("zmq_ctx_term" %zmq-ctx-term) :int (context :pointer))
(cffi:defcfun ("zmq_ctx_shutdown" %zmq-ctx-shutdown) :int (context :pointer))
(cffi:defcfun ("zmq_ctx_set" %zmq-ctx-set) :int
  (context :pointer) (option :int) (optval :int))
(cffi:defcfun ("zmq_ctx_get" %zmq-ctx-get) :int
  (context :pointer) (option :int))

;;; messages

(cffi:defcfun ("zmq_msg_init" %zmq-msg-init) :int (msg :pointer))
(cffi:defcfun ("zmq_msg_init_size" %zmq-msg-init-size) :int
  (msg :pointer) (size :size))
(cffi:defcfun ("zmq_msg_send" %zmq-msg-send) :int
  (msg :pointer) (socket :pointer) (flags :int))
(cffi:defcfun ("zmq_msg_recv" %zmq-msg-recv) :int
  (msg :pointer) (socket :pointer) (flags :int))
(cffi:defcfun ("zmq_msg_close" %zmq-msg-close) :int (msg :pointer))
(cffi:defcfun ("zmq_msg_data" %zmq-msg-data) :pointer (msg :pointer))
(cffi:defcfun ("zmq_msg_size" %zmq-msg-size) :size (msg :pointer))
(cffi:defcfun ("zmq_msg_more" %zmq-msg-more) :int (msg :pointer))

;;; sockets

(cffi:defcfun ("zmq_socket" %zmq-socket) :pointer
  (context :pointer) (type :int))
(cffi:defcfun ("zmq_close" %zmq-close) :int (socket :pointer))
(cffi:defcfun ("zmq_setsockopt" %zmq-setsockopt) :int
  (socket :pointer) (option :int) (optval :pointer) (optvallen :size))
(cffi:defcfun ("zmq_getsockopt" %zmq-getsockopt) :int
  (socket :pointer) (option :int) (optval :pointer) (optvallen (:pointer :size)))
(cffi:defcfun ("zmq_bind" %zmq-bind) :int (socket :pointer) (addr :string))
(cffi:defcfun ("zmq_connect" %zmq-connect) :int (socket :pointer) (addr :string))
(cffi:defcfun ("zmq_unbind" %zmq-unbind) :int (socket :pointer) (addr :string))
(cffi:defcfun ("zmq_disconnect" %zmq-disconnect) :int
  (socket :pointer) (addr :string))
(cffi:defcfun ("zmq_send" %zmq-send) :int
  (socket :pointer) (buf :pointer) (len :size) (flags :int))
(cffi:defcfun ("zmq_socket_monitor" %zmq-socket-monitor) :int
  (socket :pointer) (addr :string) (events :int))

;;; polling and proxies

(cffi:defcfun ("zmq_poll" %zmq-poll) :int
  (items :pointer) (nitems :int) (timeout :long))
(cffi:defcfun ("zmq_proxy" %zmq-proxy) :int
  (frontend :pointer) (backend :pointer) (capture :pointer))
(cffi:defcfun ("zmq_proxy_steerable" %zmq-proxy-steerable) :int
  (frontend :pointer) (backend :pointer) (capture :pointer) (control :pointer))

;;; encryption helpers

(cffi:defcfun ("zmq_z85_encode" %zmq-z85-encode) :pointer
  (dest :pointer) (data :pointer) (size :size))
(cffi:defcfun ("zmq_z85_decode" %zmq-z85-decode) :pointer
  (dest :pointer) (string :pointer))
(cffi:defcfun ("zmq_curve_keypair" %zmq-curve-keypair) :int
  (public :pointer) (secret :pointer))
(cffi:defcfun ("zmq_curve_public" %zmq-curve-public) :int
  (public :pointer) (secret :pointer))

;;; libc, for bulk copies between foreign memory and Lisp vectors

(cffi:defcfun ("memcpy" %memcpy) :pointer
  (dest :pointer) (src :pointer) (n :size))
