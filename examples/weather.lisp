;;;; weather.lisp — publish/subscribe weather updates
;;;;
;;;; In one REPL:     (zmq5-examples:weather-server)
;;;; In another:      (zmq5-examples:weather-client :zipcode "10001")
;;;;
;;;; Load hello.lisp first; it defines the package.

(in-package #:zmq5-examples)

(defun weather-server (&key (endpoint "tcp://*:5556"))
  "Publish random weather updates as \"ZIPCODE TEMPERATURE HUMIDITY\"."
  (zmq5:with-context (ctx)
    (zmq5:with-socket (publisher ctx :pub)
      (zmq5:bind publisher endpoint)
      (loop
        (zmq5:send publisher
                   (format nil "~5,'0D ~D ~D"
                           (random 100000) (- (random 215) 80) (+ 10 (random 50))))))))

(defun weather-client (&key (endpoint "tcp://localhost:5556")
                            (zipcode "10001") (count 20))
  "Average the temperature over COUNT updates for ZIPCODE."
  (zmq5:with-context (ctx)
    (zmq5:with-socket (subscriber ctx :sub :linger 0)
      (zmq5:connect subscriber endpoint)
      (zmq5:subscribe subscriber zipcode)
      (let ((total 0))
        (dotimes (i count)
          (let* ((update (zmq5:recv-string subscriber))
                 (temperature (parse-integer update :start 6 :junk-allowed t)))
            (incf total temperature)))
        (format t "Average temperature for ~A was ~,1F F~%"
                zipcode (/ total count))))))
