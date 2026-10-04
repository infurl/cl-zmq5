;;;; extras.lisp — proxies, socket monitoring and CURVE/Z85 helpers

(in-package #:zmq5)

;;; Proxies

(defun optional-handle (socket)
  (if socket (socket-handle socket) (cffi:null-pointer)))

(defun proxy (frontend backend &optional capture)
  "Shuttle messages between FRONTEND and BACKEND, copying every message
to CAPTURE if given.  This blocks the calling thread until the context
is terminated or shut down, and then returns NIL."
  (handler-case
      (retrying-eintr "zmq_proxy"
                      (%zmq-proxy (socket-handle frontend)
                                  (socket-handle backend)
                                  (optional-handle capture)))
    (zmq-terminated () nil)))

(defun proxy-steerable (frontend backend control &optional capture)
  "Like PROXY, but CONTROL is a socket that accepts the commands
\"PAUSE\", \"RESUME\", \"TERMINATE\" and \"STATISTICS\".  Return T
after a TERMINATE command, NIL if the context was terminated."
  (handler-case
      (progn
        (retrying-eintr "zmq_proxy_steerable"
                        (%zmq-proxy-steerable (socket-handle frontend)
                                              (socket-handle backend)
                                              (optional-handle capture)
                                              (socket-handle control)))
        t)
    (zmq-terminated () nil)))

;;; Socket monitoring

(defun monitor (socket endpoint &key (events :all))
  "Publish events about SOCKET's connections on ENDPOINT, which must be
an inproc:// address.  Connect a :PAIR socket to it and read the events
with RECV-MONITOR-EVENT.  EVENTS is a keyword or list of keywords such as
:CONNECTED, :LISTENING, :ACCEPTED, :DISCONNECTED or :ALL.  An ENDPOINT
of NIL stops monitoring."
  (check-rc "zmq_socket_monitor"
            (%zmq-socket-monitor (socket-handle socket)
                                 (or endpoint (cffi:null-pointer))
                                 (events-to-int events *monitor-events*)))
  (values))

(defun recv-monitor-event (socket &key dontwait)
  "Receive an event from SOCKET, a :PAIR socket connected to a MONITOR
endpoint.  Return three values: the event keyword, its integer value
(a file descriptor, errno or interval depending on the event) and the
endpoint it concerns."
  (destructuring-bind (header endpoint &rest rest)
      (recv-multipart socket :dontwait dontwait)
    (declare (ignore rest))
    (cffi:with-pointer-to-vector-data (pointer header)
      (values (reverse-lookup (cffi:mem-ref pointer :uint16 0)
                              *monitor-events*)
              (cffi:mem-ref pointer :uint32 2)
              (decode endpoint :utf-8)))))

;;; Z85 and CURVE keys

(defun z85-encode (data)
  "Encode DATA, an octet vector whose length is a multiple of 4, as a
Z85 string."
  (with-octets (source size data)
    (unless (zerop (mod size 4))
      (error "Z85 input length must be a multiple of 4, not ~D." size))
    (let ((chars (* 5 (/ size 4))))
      (cffi:with-foreign-object (dest :char (1+ chars))
        (when (cffi:null-pointer-p (%zmq-z85-encode dest source size))
          (error "zmq_z85_encode failed."))
        (cffi:foreign-string-to-lisp dest :count chars :encoding :ascii)))))

(defun z85-decode (string)
  "Decode a Z85 STRING, whose length is a multiple of 5, into octets."
  (let ((chars (length string)))
    (unless (zerop (mod chars 5))
      (error "Z85 string length must be a multiple of 5, not ~D." chars))
    (let ((size (* 4 (/ chars 5))))
      (cffi:with-foreign-object (dest :uint8 (max size 1))
        (cffi:with-foreign-string (source string :encoding :ascii)
          (when (cffi:null-pointer-p (%zmq-z85-decode dest source))
            (error "Invalid Z85 string: ~S" string)))
        (foreign-to-octets dest size)))))

(defun curve-keypair ()
  "Generate a new CURVE key pair.  Return two Z85 strings: the public
key and the secret key.  Requires libzmq built with CURVE support."
  (cffi:with-foreign-objects ((public :char 41) (secret :char 41))
    (check-rc "zmq_curve_keypair" (%zmq-curve-keypair public secret))
    (values (cffi:foreign-string-to-lisp public :encoding :ascii)
            (cffi:foreign-string-to-lisp secret :encoding :ascii))))

(defun curve-public (secret-key)
  "Return the Z85 public key for SECRET-KEY, a Z85 string."
  (cffi:with-foreign-object (public :char 41)
    (cffi:with-foreign-string (secret secret-key :encoding :ascii)
      (check-rc "zmq_curve_public" (%zmq-curve-public public secret)))
    (cffi:foreign-string-to-lisp public :encoding :ascii)))
