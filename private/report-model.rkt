#lang racket/base

(require racket/list
         racket/set
         racket/vector
         "model.rkt"
         "definition-registry.rkt"
         "common-lab-definitions.rkt")

(provide (struct-out hl7-report)
         (struct-out report-segment)
         (struct-out report-field)
         (struct-out report-unparsed)
         parse-result->report
         report-segment-visible-fields)

;; This model is the immutable boundary between parser ADTs and presentation.
;; It keeps encoded values and parser spans intact; terminology is resolved only
;; through the supplied private registry.
(struct hl7-report
  (message-version parts diagnostics complete? provenances definition-sources)
  #:transparent)

(struct report-segment
  (path name label occurrence fields span provenance node)
  #:transparent)

(struct report-field
  (path position label raw span provenance empty?)
  #:transparent)

(struct report-unparsed (label raw span diagnostic) #:transparent)

(define (immutable-vector values)
  (vector->immutable-vector (list->vector values)))

(define (message-version message)
  (define msh (and message (hl7-message-segment message "MSH")))
  (define field (and msh (hl7-segment-field msh 12)))
  (and field
       (not (string=? (hl7-field-raw field) ""))
       (hl7-field-raw field)))

(define (report-segment-visible-fields segment include-empty?)
  (unless (report-segment? segment)
    (raise-argument-error
     'report-segment-visible-fields "report-segment?" segment))
  (unless (boolean? include-empty?)
    (raise-argument-error
     'report-segment-visible-fields "boolean?" include-empty?))
  (vector->immutable-vector
   (for/vector ([field (in-vector (report-segment-fields segment))]
                #:when (or include-empty? (not (report-field-empty? field))))
     field)))

(define (diagnostic-for-span diagnostics span)
  (for/first ([diagnostic (in-vector diagnostics)]
              #:when
              (<= (hl7-span-start span)
                  (hl7-span-start (hl7-diagnostic-span diagnostic))
                  (hl7-span-end span)))
    diagnostic))

(define (record-resolution! provenances sources resolved)
  (set-add! provenances (resolved-definition-provenance resolved))
  (define source (resolved-definition-source-identifier resolved))
  (when source
    (set-add! sources source)))

(define (parse-result->report result [registry common-lab-registry])
  (unless (hl7-parse-result? result)
    (raise-argument-error 'parse-result->report "hl7-parse-result?" result))
  (unless (definition-registry? registry)
    (raise-argument-error 'parse-result->report
                          "definition-registry?"
                          registry))
  (define message (hl7-parse-result-message result))
  (define version (message-version message))
  (define occurrences (make-hash))
  (define used-provenances (mutable-set))
  (define used-definition-sources (mutable-set))
  (define parts
    (if message
        (immutable-vector
         (for/list ([part (in-vector (hl7-message-parts message))])
           (cond
             [(hl7-segment? part)
              (define name (hl7-segment-name part))
              (define occurrence (add1 (hash-ref occurrences name 0)))
              (hash-set! occurrences name occurrence)
              (define segment-definition
                (resolve-segment-definition registry name version))
              (record-resolution! used-provenances
                                  used-definition-sources
                                  segment-definition)
              (define fields
                (immutable-vector
                 (for/list ([field (in-vector (hl7-segment-fields part))]
                            [position (in-naturals 1)])
                   (define field-definition
                     (resolve-field-definition
                      registry name position version))
                   (record-resolution! used-provenances
                                       used-definition-sources
                                       field-definition)
                   (define raw (hl7-field-raw field))
                   (report-field
                    (format "~a[~a]-~a" name occurrence position)
                    position
                    (resolved-definition-label field-definition)
                    raw
                    (hl7-field-span field)
                    (resolved-definition-provenance field-definition)
                    (string=? raw "")))))
              (report-segment
               (format "~a[~a]" name occurrence)
               name
               (resolved-definition-label segment-definition)
               occurrence
               fields
               (hl7-segment-span part)
               (resolved-definition-provenance segment-definition)
               part)]
             [(hl7-unparsed-segment? part)
              (define span (hl7-unparsed-segment-span part))
              (report-unparsed
               (format "Unparsed segment @ ~a:~a"
                       (hl7-span-start span)
                       (hl7-span-end span))
               (hl7-unparsed-segment-raw part)
               span
               (diagnostic-for-span
                (hl7-parse-result-diagnostics result) span))]
             [else
              (raise-arguments-error
               'parse-result->report
               "message contains an unsupported parser part"
               "part" part)])))
        (immutable-vector '())))
  (hl7-report
   version
   parts
   (hl7-parse-result-diagnostics result)
   (hl7-parse-result-complete? result)
   (immutable-vector (sort (set->list used-provenances) symbol<?))
   (immutable-vector (sort (set->list used-definition-sources) symbol<?))))
