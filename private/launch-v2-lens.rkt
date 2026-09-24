#lang racket/base

(require "../gui.rkt")

(cond
  [(equal? (current-command-line-arguments) '#("--smoke-test"))
   (with-handlers ([exn:fail?
                    (lambda (failure)
                      (eprintf "V2_LENS_SMOKE_FAILED: ~a\n" (exn-message failure))
                      (exit 1))])
     (run-v2-lens-smoke-test)
     (displayln "V2_LENS_SMOKE_OK")
     (flush-output)
     (exit 0))]
  [else (run-v2-lens)])
