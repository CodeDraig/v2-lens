#lang racket/base

(require rackunit
         "../main.rkt"
         "../private/gui-model.rkt"
         "../private/report-model.rkt")

(module+ test
  (define complete (parse-hl7-v2 "MSH|^~\\&|APP\rPID|1"))
  (check-equal? (parse-result->status complete)
                "Complete — 2 segments, 0 unparsed parts, 0 diagnostics")

  (define fatal (parse-hl7-v2 "PID|1"))
  (check-equal? (parse-result->status fatal)
                "Incomplete — 0 segments, 0 unparsed parts, 1 diagnostics")
  (check-true
   (regexp-match?
    #rx"missing-msh"
    (diagnostic->label
     (vector-ref (hl7-parse-result-diagnostics fatal) 0))))

  (check-equal?
   (report->interpretation-label (parse-result->report complete))
   (string-append
    "Labels use common HL7 v2 terminology. Message version: not identified. "
    "Schema validation and value interpretation were not performed."))

  (check-exn exn:fail:contract?
             (lambda () (diagnostic->label #f)))
  (check-exn exn:fail:contract?
             (lambda () (parse-result->status #f)))
  (check-exn exn:fail:contract?
             (lambda () (report->interpretation-label #f))))
