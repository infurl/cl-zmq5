;;;; poll.lisp — I/O multiplexing with zmq_poll

(in-package #:zmq5)

(defun remaining-ms (deadline)
  "Milliseconds until DEADLINE, in internal real time units, or -1."
  (if deadline
      (max 0 (ceiling (* 1000 (- deadline (get-internal-real-time)))
                      internal-time-units-per-second))
      -1))

(defun poll (items &key timeout)
  "Wait for events on several sockets or file descriptors at once.

ITEMS is a list whose elements look like (TARGET EVENT...), where TARGET
is a SOCKET or an integer file descriptor and each EVENT is one of
:POLLIN, :POLLOUT, :POLLERR or :POLLPRI.  For example:

  (poll (list (list frontend :pollin) (list backend :pollin :pollout))
        :timeout 1000)

TIMEOUT is in milliseconds; NIL (the default) waits indefinitely and 0
returns at once.  Return two values: a list with, for each item in
order, the list of events that occurred on it (NIL for none), and the
number of items with events."
  (let* ((count (length items))
         (deadline (when (and timeout (plusp timeout))
                     (+ (get-internal-real-time)
                        (ceiling (* timeout internal-time-units-per-second)
                                 1000)))))
    (cffi:with-foreign-object (array '(:struct pollitem) count)
      (loop for (target . events) in items
            for i from 0
            for item = (cffi:mem-aptr array '(:struct pollitem) i)
            do (etypecase target
                 (socket (setf (pollitem-socket item) (socket-handle target)
                               (pollitem-fd item) 0))
                 (integer (setf (pollitem-socket item) (cffi:null-pointer)
                                (pollitem-fd item) target)))
               (setf (pollitem-events item) (events-to-int events *poll-events*)
                     (pollitem-revents item) 0))
      (let ((ready
              (loop
                (let ((rc (%zmq-poll array count
                                     (cond ((null timeout) -1)
                                           (deadline (remaining-ms deadline))
                                           (t 0)))))
                  (cond ((>= rc 0) (return rc))
                        ((/= (%zmq-errno) +eintr+)
                         (signal-zmq-error (%zmq-errno) "zmq_poll")))))))
        (values (loop for i below count
                      collect (int-to-events
                               (pollitem-revents
                                (cffi:mem-aptr array '(:struct pollitem) i))
                               *poll-events*))
                ready)))))
