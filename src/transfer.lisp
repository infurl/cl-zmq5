;;;; transfer.lisp — sending and receiving messages

(in-package #:zmq5)

(defun send (socket data &key more dontwait (encoding :utf-8))
  "Send DATA as one message part on SOCKET and return its size in octets.
DATA is an octet vector, a string (encoded with ENCODING) or NIL (an
empty part).  With MORE true, further parts of the same message follow.
With DONTWAIT true, signal ZMQ-AGAIN instead of blocking when the
message cannot be queued."
  (let ((handle (socket-handle socket))
        (flags (logior (if more +sndmore+ 0) (if dontwait +dontwait+ 0))))
    (with-octets (pointer length data encoding)
      (retrying-eintr "zmq_send" (%zmq-send handle pointer length flags)))))

(defun send-multipart (socket parts &key dontwait (encoding :utf-8))
  "Send the list PARTS as a single multi-part message.  See SEND."
  (when (null parts)
    (error "Cannot send a message with no parts."))
  (loop for (part . rest) on parts
        do (send socket part :more rest :dontwait dontwait
                             :encoding encoding))
  (values))

(defun recv (socket &key dontwait (as :octets) (encoding :utf-8))
  "Receive one message part from SOCKET.  Return two values: the data
and a boolean that is true when more parts of the message follow.
The data is an octet vector, or a string decoded with ENCODING when AS
is :STRING.  With DONTWAIT true, signal ZMQ-AGAIN instead of blocking."
  (check-type as (member :octets :string))
  (let ((handle (socket-handle socket))
        (flags (if dontwait +dontwait+ 0)))
    (with-msg (msg)
      (check-rc "zmq_msg_init" (%zmq-msg-init msg))
      (unwind-protect
           (progn
             (retrying-eintr "zmq_msg_recv" (%zmq-msg-recv msg handle flags))
             (let ((octets (foreign-to-octets (%zmq-msg-data msg)
                                              (%zmq-msg-size msg))))
               (values (if (eq as :string) (decode octets encoding) octets)
                       (/= 0 (%zmq-msg-more msg)))))
        (%zmq-msg-close msg)))))

(defun recv-string (socket &key dontwait (encoding :utf-8))
  "Receive one message part as a string.  See RECV."
  (recv socket :dontwait dontwait :as :string :encoding encoding))

(defun recv-multipart (socket &key dontwait (as :octets) (encoding :utf-8))
  "Receive every part of the next message and return them as a list.
See RECV for the keyword arguments.  Message parts are delivered
atomically, so DONTWAIT only affects waiting for the first part."
  (loop for (part more) = (multiple-value-list
                           (recv socket :dontwait dontwait :as as
                                        :encoding encoding))
        collect part
        while more))
