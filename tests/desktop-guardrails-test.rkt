#lang racket/base

(require racket/file
         rackunit
         "../private/desktop-guardrails.rkt")

(module+ test
  (check-equal? max-parse-bytes (* 5 1024 1024))
  (check-equal? max-open-file-bytes (* 100 1024 1024))

  (define header "MSH|^~\\&|")
  (define exact-size-source
    (string-append header
                   (make-string (- max-parse-bytes
                                   (string-utf-8-length header))
                                #\X)))
  (check-false (source-parse-refusal exact-size-source))
  (check-regexp-match
   #rx"exceeds the 5 MiB public beta parse limit"
   (source-parse-refusal (string-append exact-size-source "X")))

  (define exact-budget-source
    (string-append "MSH|^~\\&"
                   (make-string (- max-structural-delimiters 5) #\|)))
  (check-equal? (source-structural-delimiter-count exact-budget-source)
                max-structural-delimiters)
  (check-false (source-parse-refusal exact-budget-source))
  (check-regexp-match
   #rx"structural delimiters exceeds"
   (source-parse-refusal (string-append exact-budget-source "|")))

  (check-equal? (bounded-control-label "short") "short")
  (check-equal? (bounded-control-label "a\nb" 3) "a�b")
  (check-equal? (bounded-control-label "abcdef" 5) "abcd…")
  (check-equal? (string-length
                 (bounded-control-label
                  (make-string 1000 #\X)))
                max-field-control-label-length)

  (define sparse-path (make-temporary-file "v2-lens-size-guard-~a.hl7"))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file sparse-path
       (lambda (output)
         (file-position output (sub1 max-open-file-bytes))
         (write-byte 0 output)
         (flush-output output)
         (check-equal? (file-size sparse-path) max-open-file-bytes)
         (check-false (file-open-refusal sparse-path))
         (file-position output max-open-file-bytes)
         (write-byte 0 output))
       #:exists 'truncate/replace
       #:mode 'binary)
     (check-equal? (file-size sparse-path) (add1 max-open-file-bytes))
     (check-regexp-match #rx"exceeds the 100 MiB public beta limit"
                         (file-open-refusal sparse-path)))
   (lambda ()
     (delete-file sparse-path))))
