#lang racket/base

(require rackunit)

(define gtk-display-failure-rx
  #rx"^Gtk initialization failed for display ")

(define (gui-display-unavailable? problem)
  (and (exn:fail? problem)
       (regexp-match? gtk-display-failure-rx (exn-message problem))))

(define (attempt-gui-load load!)
  (with-handlers ([gui-display-unavailable? (lambda (_problem) #f)])
    (load!)
    #t))

(module+ test
  (check-false
   (attempt-gui-load
    (lambda ()
      (error "Gtk initialization failed for display \":0\""))))
  (check-exn
   #rx"unrelated GUI initialization failure"
   (lambda ()
     (attempt-gui-load
      (lambda ()
        (error "unrelated GUI initialization failure")))))

  (define gui-loaded?
    (attempt-gui-load
     (lambda ()
       (dynamic-require 'racket/gui/base #f))))

  (when gui-loaded?
    (test-case "GUI report navigation smoke contract"
      (dynamic-require '(submod "../gui.rkt" test) #f))))
