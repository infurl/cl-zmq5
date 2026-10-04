# Makefile for zmq5
#
# Dependencies (cffi, babel) are found through ASDF's normal source
# registry (e.g. Debian's cl-cffi package) or Quicklisp, if installed.

SBCL       ?= sbcl
QUICKLISP  ?= $(HOME)/quicklisp/setup.lisp
LISP_FLAGS  = --noinform --non-interactive

LOAD = --eval '(require :asdf)' \
       --eval '(let ((ql (probe-file "$(QUICKLISP)"))) (when ql (load ql)))' \
       --eval '(push (truename ".") asdf:*central-registry*)'

.PHONY: all build test clean

all: build

build:
	$(SBCL) $(LISP_FLAGS) $(LOAD) --eval '(asdf:load-system "zmq5")'

test:
	$(SBCL) $(LISP_FLAGS) $(LOAD) --eval '(asdf:test-system "zmq5")'

clean:
	find . -name '*.fasl' -delete
