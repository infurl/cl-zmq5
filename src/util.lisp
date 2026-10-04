;;;; util.lisp — conversions between Lisp data and foreign memory

(in-package #:zmq5)

(deftype octets () '(simple-array (unsigned-byte 8) (*)))

(defun make-octets (size)
  (cffi:make-shareable-byte-vector size))

(defun to-octets (data &optional (encoding :utf-8))
  "Coerce DATA to a simple octet vector.  Strings are encoded with
ENCODING, NIL becomes the empty vector."
  (etypecase data
    (octets data)
    (string (babel:string-to-octets data :encoding encoding))
    (null (make-octets 0))
    (vector (let ((v (make-octets (length data))))
              (replace v data)))))

(defun foreign-to-octets (pointer size)
  "Copy SIZE octets starting at POINTER into a fresh octet vector."
  (let ((vector (make-octets size)))
    (when (plusp size)
      (cffi:with-pointer-to-vector-data (dest vector)
        (%memcpy dest pointer size)))
    vector))

(defun decode (octets encoding)
  (babel:octets-to-string octets :encoding encoding))

(defmacro with-octets ((pointer length data &optional (encoding :utf-8))
                       &body body)
  "Bind POINTER to foreign memory holding DATA (see TO-OCTETS) and LENGTH
to its size in octets.  The data is pinned, not copied, where possible."
  (let ((vector (gensym "VECTOR")))
    `(let* ((,vector (to-octets ,data ,encoding))
            (,length (length ,vector)))
       (cffi:with-pointer-to-vector-data (,pointer ,vector)
         ,@body))))
