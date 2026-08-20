#lang racket/base

(require racket/string
         "model.rkt"
         "report-model.rkt")

(provide diagnostic->label
         parse-result->status
         report->interpretation-label)

(define (diagnostic->label diagnostic)
  (unless (hl7-diagnostic? diagnostic)
    (raise-argument-error 'diagnostic->label "hl7-diagnostic?" diagnostic))
  (define span (hl7-diagnostic-span diagnostic))
  (format "~a — ~a (~a:~a)"
          (hl7-diagnostic-code diagnostic)
          (hl7-diagnostic-message diagnostic)
          (hl7-span-start span)
          (hl7-span-end span)))

(define (parse-result->status result)
  (unless (hl7-parse-result? result)
    (raise-argument-error 'parse-result->status "hl7-parse-result?" result))
  (define message (hl7-parse-result-message result))
  (define segment-count
    (if message (vector-length (hl7-message-segments message)) 0))
  (define unparsed-count
    (if message (vector-length (hl7-message-unparsed-parts message)) 0))
  (define diagnostic-count
    (vector-length (hl7-parse-result-diagnostics result)))
  (format "~a — ~a segments, ~a unparsed parts, ~a diagnostics"
          (if (hl7-parse-result-complete? result) "Complete" "Incomplete")
          segment-count
          unparsed-count
          diagnostic-count))

(define (report->interpretation-label report)
  (unless (hl7-report? report)
    (raise-argument-error
     'report->interpretation-label "hl7-report?" report))
  (define version (or (hl7-report-message-version report) "not identified"))
  (define provenances (vector->list (hl7-report-provenances report)))
  (define source-prefix
    (cond
      [(member 'version-specific provenances)
       (define sources
         (string-join
          (map symbol->string
               (vector->list (hl7-report-definition-sources report)))
          ", "))
       (if (member 'common provenances)
           (format "Labels use ~a definitions with common HL7 v2 fallback."
                   sources)
           (format "Labels use ~a definitions." sources))]
      [else "Labels use common HL7 v2 terminology."]))
  (format (string-append
           "~a Message version: ~a. "
           "Schema validation and value interpretation were not performed.")
          source-prefix
          version))
