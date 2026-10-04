;;;; errors.lisp — conditions and error checking

(in-package #:zmq5)

(define-condition zmq-error (error)
  ((errno :initarg :errno :reader zmq-error-errno
          :documentation "The numeric error code reported by zmq_errno().")
   (function :initarg :function :initform nil :reader zmq-error-function
             :documentation "Name of the libzmq function that failed."))
  (:report (lambda (condition stream)
             (format stream "ZeroMQ error~@[ in ~A~]: ~A (~A)"
                     (zmq-error-function condition)
                     (%zmq-strerror (zmq-error-errno condition))
                     (zmq-error-name condition))))
  (:documentation "Signalled when a libzmq function reports failure."))

(defun zmq-error-name (condition)
  "Return the errno keyword of CONDITION (e.g. :EINVAL), or the number
if it is not one we know by name."
  (reverse-lookup (zmq-error-errno condition) *errnos*))

(define-condition zmq-again (zmq-error) ()
  (:documentation "EAGAIN: the operation would block.  Signalled by
non-blocking sends and receives, and when :SNDTIMEO or :RCVTIMEO expire."))

(define-condition zmq-terminated (zmq-error) ()
  (:documentation "ETERM: the socket's context was terminated or shut down."))

(defun signal-zmq-error (errno function)
  (error (cond ((eql errno *eagain*) 'zmq-again)
               ((eql errno +eterm+) 'zmq-terminated)
               (t 'zmq-error))
         :errno errno :function function))

(defmacro check-rc (function form)
  "Evaluate FORM, a call to a libzmq function returning an int.  Signal a
ZMQ-ERROR if the result is negative, otherwise return the result."
  (let ((rc (gensym "RC")))
    `(let ((,rc ,form))
       (if (minusp ,rc)
           (signal-zmq-error (%zmq-errno) ,function)
           ,rc))))

(defmacro retrying-eintr (function form)
  "Like CHECK-RC, but retry FORM if it was interrupted by a signal.
Lisp runtimes deliver signals for their own purposes (SBCL stops threads
for garbage collection that way), so any blocking call can fail with EINTR."
  (let ((rc (gensym "RC")) (errno (gensym "ERRNO")))
    `(loop
       (let ((,rc ,form))
         (if (minusp ,rc)
             (let ((,errno (%zmq-errno)))
               (unless (eql ,errno +eintr+)
                 (signal-zmq-error ,errno ,function)))
             (return ,rc))))))
