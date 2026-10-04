;;;; constants.lisp — keyword <-> integer tables for libzmq constants
;;;;
;;;; Values are taken from zmq.h of libzmq 4.3.  They are part of the
;;;; stable ABI, so we hardcode them rather than grovelling (which would
;;;; need a C compiler and the zmq headers at build time).

(in-package #:zmq5)

(defun lookup (key table what)
  "Return the integer for KEY in TABLE (an alist).  Integers pass through."
  (if (integerp key)
      key
      (let ((entry (assoc key table)))
        (unless entry
          (error "Unknown ZeroMQ ~A: ~S~%Valid values are: ~{~S~^ ~}"
                 what key (mapcar #'car table)))
        (cdr entry))))

(defun reverse-lookup (value table)
  "Return the keyword whose value in TABLE is VALUE, or VALUE itself."
  (or (car (rassoc value table)) value))

;;; Socket types

(defparameter *socket-types*
  '((:pair . 0) (:pub . 1) (:sub . 2) (:req . 3) (:rep . 4)
    (:dealer . 5) (:router . 6) (:pull . 7) (:push . 8)
    (:xpub . 9) (:xsub . 10) (:stream . 11)))

;;; Flags for send and receive

(defconstant +dontwait+ 1)
(defconstant +sndmore+ 2)

;;; Context options.  zmq_ctx_set/zmq_ctx_get only deal in ints.

(defparameter *context-options*
  '((:io-threads . 1) (:max-sockets . 2) (:socket-limit . 3)
    (:thread-priority . 3) (:thread-sched-policy . 4) (:max-msgsz . 5)
    (:msg-t-size . 6) (:thread-affinity-cpu-add . 7)
    (:thread-affinity-cpu-remove . 8) (:thread-name-prefix . 9)
    (:ipv6 . 42) (:blocky . 70)))

(defparameter *boolean-context-options* '(:ipv6 :blocky))

;;; Socket options: (keyword code type).  TYPE is one of
;;;   :int      C int
;;;   :boolean  C int holding 0 or 1, exposed as NIL / T
;;;   :int64    int64_t
;;;   :uint64   uint64_t
;;;   :bytes    binary data, exposed as an octet vector
;;;   :string   character data, exposed as a string
;;;   :key      CURVE key: 32 raw octets or a 40-character Z85 string;
;;;             read back as a Z85 string

(defparameter *socket-options*
  '((:affinity 4 :uint64)
    (:routing-id 5 :bytes)
    (:identity 5 :bytes)                ; deprecated alias of :routing-id
    (:subscribe 6 :bytes)
    (:unsubscribe 7 :bytes)
    (:rate 8 :int)
    (:recovery-ivl 9 :int)
    (:sndbuf 11 :int)
    (:rcvbuf 12 :int)
    (:rcvmore 13 :boolean)
    (:fd 14 :int)
    (:events 15 :int)
    (:type 16 :int)
    (:linger 17 :int)
    (:reconnect-ivl 18 :int)
    (:backlog 19 :int)
    (:reconnect-ivl-max 21 :int)
    (:maxmsgsize 22 :int64)
    (:sndhwm 23 :int)
    (:rcvhwm 24 :int)
    (:multicast-hops 25 :int)
    (:rcvtimeo 27 :int)
    (:sndtimeo 28 :int)
    (:ipv4only 31 :boolean)
    (:last-endpoint 32 :string)
    (:router-mandatory 33 :boolean)
    (:tcp-keepalive 34 :int)
    (:tcp-keepalive-cnt 35 :int)
    (:tcp-keepalive-idle 36 :int)
    (:tcp-keepalive-intvl 37 :int)
    (:tcp-accept-filter 38 :string)
    (:immediate 39 :boolean)
    (:xpub-verbose 40 :boolean)
    (:router-raw 41 :boolean)
    (:ipv6 42 :boolean)
    (:mechanism 43 :int)
    (:plain-server 44 :boolean)
    (:plain-username 45 :string)
    (:plain-password 46 :string)
    (:curve-server 47 :boolean)
    (:curve-publickey 48 :key)
    (:curve-secretkey 49 :key)
    (:curve-serverkey 50 :key)
    (:probe-router 51 :boolean)
    (:req-correlate 52 :boolean)
    (:req-relaxed 53 :boolean)
    (:conflate 54 :boolean)
    (:zap-domain 55 :string)
    (:router-handover 56 :boolean)
    (:tos 57 :int)
    (:ipc-filter-pid 58 :int)
    (:ipc-filter-uid 59 :int)
    (:ipc-filter-gid 60 :int)
    (:connect-routing-id 61 :bytes)
    (:gssapi-server 62 :boolean)
    (:gssapi-principal 63 :string)
    (:gssapi-service-principal 64 :string)
    (:gssapi-plaintext 65 :boolean)
    (:handshake-ivl 66 :int)
    (:socks-proxy 68 :string)
    (:xpub-nodrop 69 :boolean)
    (:xpub-manual 71 :boolean)
    (:xpub-welcome-msg 72 :bytes)
    (:stream-notify 73 :boolean)
    (:invert-matching 74 :boolean)
    (:heartbeat-ivl 75 :int)
    (:heartbeat-ttl 76 :int)
    (:heartbeat-timeout 77 :int)
    (:xpub-verboser 78 :boolean)
    (:connect-timeout 79 :int)
    (:tcp-maxrt 80 :int)
    (:thread-safe 81 :boolean)
    (:multicast-maxtpdu 84 :int)
    (:vmci-buffer-size 85 :uint64)
    (:vmci-buffer-min-size 86 :uint64)
    (:vmci-buffer-max-size 87 :uint64)
    (:vmci-connect-timeout 88 :int)
    (:use-fd 89 :int)
    (:gssapi-principal-nametype 90 :int)
    (:gssapi-service-principal-nametype 91 :int)
    (:bindtodevice 92 :string)))

(defun socket-option-info (name)
  "Return (values code type) for the socket option NAME."
  (let ((entry (assoc name *socket-options*)))
    (unless entry
      (error "Unknown ZeroMQ socket option: ~S~%Valid options are: ~{~S~^ ~}"
             name (mapcar #'first *socket-options*)))
    (values (second entry) (third entry))))

;;; Security mechanisms, as returned by the :MECHANISM option

(defparameter *mechanisms*
  '((:null . 0) (:plain . 1) (:curve . 2) (:gssapi . 3)))

;;; Poll events

(defparameter *poll-events*
  '((:pollin . 1) (:pollout . 2) (:pollerr . 4) (:pollpri . 8)))

(defun events-to-int (events table)
  "Turn a keyword, an integer or a list of keywords into a bit mask."
  (cond ((integerp events) events)
        ((keywordp events) (lookup events table "event"))
        (t (reduce #'logior events
                   :key (lambda (e) (lookup e table "event"))
                   :initial-value 0))))

(defun int-to-events (int table)
  "Turn a bit mask into a list of keywords."
  (loop for (key . bit) in table
        when (logtest int bit) collect key))

;;; Socket monitor events

(defparameter *monitor-events*
  '((:connected . #x0001) (:connect-delayed . #x0002)
    (:connect-retried . #x0004) (:listening . #x0008)
    (:bind-failed . #x0010) (:accepted . #x0020)
    (:accept-failed . #x0040) (:closed . #x0080)
    (:close-failed . #x0100) (:disconnected . #x0200)
    (:monitor-stopped . #x0400) (:handshake-failed-no-detail . #x0800)
    (:handshake-succeeded . #x1000) (:handshake-failed-protocol . #x2000)
    (:handshake-failed-auth . #x4000) (:all . #xFFFF)))

;;; Error numbers.  The native ZeroMQ codes are offset from
;;; ZMQ_HAUSNUMERO; the rest are the platform's errno values for the
;;; errors that libzmq documents.

(defconstant +hausnumero+ 156384712)

(defparameter *errnos*
  `((:efsm . ,(+ +hausnumero+ 51))
    (:enocompatproto . ,(+ +hausnumero+ 52))
    (:eterm . ,(+ +hausnumero+ 53))
    (:emthread . ,(+ +hausnumero+ 54))
    (:enoent . 2) (:eintr . 4) (:efault . 14) (:enodev . 19)
    (:einval . 22) (:emfile . 24)
    #+linux
    ,@'((:eagain . 11) (:enotsock . 88) (:emsgsize . 90)
        (:eprotonosupport . 93) (:enotsup . 95) (:eafnosupport . 97)
        (:eaddrinuse . 98) (:eaddrnotavail . 99) (:enetdown . 100)
        (:enetunreach . 101) (:enetreset . 102) (:econnaborted . 103)
        (:econnreset . 104) (:enobufs . 105) (:enotconn . 107)
        (:etimedout . 110) (:econnrefused . 111) (:ehostunreach . 113)
        (:einprogress . 115))
    #+(or darwin freebsd openbsd netbsd)
    ,@'((:eagain . 35) (:einprogress . 36) (:enotsock . 38)
        (:emsgsize . 40) (:eprotonosupport . 43) (:enotsup . 45)
        (:eafnosupport . 47) (:eaddrinuse . 48) (:eaddrnotavail . 49)
        (:enetdown . 50) (:enetunreach . 51) (:enetreset . 52)
        (:econnaborted . 53) (:econnreset . 54) (:enobufs . 55)
        (:enotconn . 57) (:etimedout . 60) (:econnrefused . 61)
        (:ehostunreach . 65))
    #+windows
    ,@'((:eagain . 11))))

(defconstant +eintr+ 4)
(defconstant +eterm+ (+ +hausnumero+ 53))
(defparameter *eagain* (cdr (assoc :eagain *errnos*)))
