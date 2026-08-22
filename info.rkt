#lang info

(define collection "v2-lens")
(define deps '("base" "gui-lib"))
(define build-deps '("rackunit-lib"))
(define version "0.1")
(define pkg-desc "V2 Lens structural HL7 v2 parser and desktop inspector for Racket")
(define pkg-authors '("CodeDraig"))
(define license 'Apache-2.0)
(define gracket-launcher-names '("v2-lens"))
(define gracket-launcher-libraries '("private/launch-v2-lens.rkt"))
(define test-omit-paths '("gui.rkt" "private/launch-v2-lens.rkt"))
