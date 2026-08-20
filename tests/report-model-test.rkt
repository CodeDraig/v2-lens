#lang racket/base

(require racket/file
         racket/list
         racket/path
         racket/runtime-path
         rackunit
         "../main.rkt"
         "../private/common-lab-definitions.rkt"
         "../private/definition-registry.rkt"
         "../private/report-model.rkt")

(define-runtime-path fixtures-directory "fixtures")

(define source
  "MSH|^~\\&|LAB|FAC|||202608181200||ORU^R01|42|P|2.5.1\rPID|1||ABC||DOE^JANE\rOBX|1|NM|HGB||13.8\rOBX|2|ST|NOTE||A~B\rZDR||LOCAL")

(define (source-slice text span)
  (substring text (hl7-span-start span) (hl7-span-end span)))

(define (segment-at report index)
  (define part (vector-ref (hl7-report-parts report) index))
  (check-true (report-segment? part))
  part)

(module+ test
  (define parsed-result (parse-hl7-v2 source))
  (define report (parse-result->report parsed-result))
  (check-true (immutable? (hl7-report-parts report)))
  (check-equal? (hl7-report-message-version report) "2.5.1")
  (check-equal? (hl7-report-definition-sources report) #(common-lab))
  (check-equal? (hl7-report-provenances report) #(common unknown))

  (define parts (hl7-report-parts report))
  (check-equal? (vector-length parts) 5)
  (define pid (segment-at report 1))
  (check-equal? (report-segment-path pid) "PID[1]")
  (check-equal? (report-segment-name pid) "PID")
  (check-equal? (report-segment-label pid) "Patient Identification")
  (check-equal? (report-segment-occurrence pid) 1)
  (define source-pid
    (hl7-message-segment (hl7-parse-result-message parsed-result) "PID"))
  (check-true (eq? (report-segment-node pid) source-pid))
  (check-equal? (report-segment-node pid) source-pid)
  (check-true (immutable? (report-segment-fields pid)))
  (define pid-3 (vector-ref (report-segment-fields pid) 2))
  (check-equal? (report-field-path pid-3) "PID[1]-3")
  (check-equal? (report-field-position pid-3) 3)
  (check-equal? (report-field-label pid-3) "Patient Identifier List")
  (check-equal? (report-field-raw pid-3) "ABC")
  (check-equal? (report-field-provenance pid-3) 'common)
  (check-false (report-field-empty? pid-3))
  (check-equal? (source-slice source (report-field-span pid-3)) "ABC")
  (check-equal? (report-field-span pid-3)
                (hl7-field-span
                 (hl7-segment-field
                  (hl7-message-segment
                   (hl7-parse-result-message (parse-hl7-v2 source)) "PID")
                  3)))

  (define obx-2 (segment-at report 3))
  (check-equal? (report-segment-path obx-2) "OBX[2]")
  (define obx-2-5 (vector-ref (report-segment-fields obx-2) 4))
  (check-equal? (report-field-raw obx-2-5) "A~B")
  (check-equal? (source-slice source (report-field-span obx-2-5)) "A~B")

  (define unknown (segment-at report 4))
  (check-equal? (report-segment-name unknown) "ZDR")
  (check-equal? (report-segment-label unknown) "Unknown segment")
  (check-equal? (report-segment-provenance unknown) 'unknown)
  (define unknown-2 (vector-ref (report-segment-fields unknown) 1))
  (check-equal? (report-field-label unknown-2) "Unknown field")
  (check-equal? (report-field-provenance unknown-2) 'unknown)

  (check-equal? (vector-length (report-segment-visible-fields pid #f)) 3)
  (check-equal? (vector-length (report-segment-visible-fields pid #t)) 5)
  (check-equal? (map report-field-position
                     (vector->list (report-segment-visible-fields pid #f)))
                '(1 3 5))
  (check-true (immutable? (report-segment-visible-fields pid #f)))
  (check-exn exn:fail:contract?
             (lambda () (report-segment-visible-fields 'not-a-segment #f)))

  (define partial
    (parse-result->report
     (parse-hl7-v2 "MSH|^~\\&|LAB|FAC|||||||P|2.3\rBAD!oops\rPID|1")))
  (check-false (hl7-report-complete? partial))
  (check-equal? (vector-length (hl7-report-parts partial)) 3)
  (define unparsed (vector-ref (hl7-report-parts partial) 1))
  (check-true (report-unparsed? unparsed))
  (check-equal? (report-unparsed-raw unparsed) "BAD!oops")
  (check-true (hl7-diagnostic? (report-unparsed-diagnostic unparsed)))
  (check-equal? (hl7-diagnostic-code (report-unparsed-diagnostic unparsed))
                'invalid-segment-name)
  (check-equal? (vector-length (hl7-report-diagnostics partial)) 1)
  (check-equal? (hl7-report-message-version partial) "2.3")

  (define fatal (parse-result->report (parse-hl7-v2 "PID|1")))
  (check-equal? (vector-length (hl7-report-parts fatal)) 0)
  (check-false (hl7-report-message-version fatal))
  (check-false (hl7-report-complete? fatal))
  (check-equal? (vector-length (hl7-report-diagnostics fatal)) 1)

  (define common
    (definition-set
     'common-lab #f #f
     (hash "OBX"
           (segment-definition "Observation Result"
                                #("Set ID - OBX"
                                  "Value Type"
                                  "Observation Identifier"
                                  "Observation Sub-ID"
                                  "Observation Value")))))
  (define v251
    (definition-set
     'test-v251 "2.5.1" "2.5.1"
     (hash "OBX"
           (segment-definition "Versioned Observation Result"
                                #(#f #f #f #f
                                  "Versioned Observation Value")))))
  (define alternate-registry (definition-registry (vector common v251)))
  (define alternate-report
    (parse-result->report (parse-hl7-v2 source) alternate-registry))
  (define alternate-obx (segment-at alternate-report 2))
  (check-equal? (report-segment-label alternate-obx)
                "Versioned Observation Result")
  (check-equal? (report-segment-provenance alternate-obx) 'version-specific)
  (check-equal? (report-field-label
                 (vector-ref (report-segment-fields alternate-obx) 4))
                "Versioned Observation Value")
  (check-equal? (report-field-provenance
                 (vector-ref (report-segment-fields alternate-obx) 4))
                'version-specific)
  (check-equal? (report-field-provenance
                 (vector-ref (report-segment-fields alternate-obx) 2))
                'common)
  (check-equal? (hl7-report-definition-sources alternate-report)
                #(common-lab test-v251))
  (check-equal? (hl7-report-message-version
                 (parse-result->report
                  (parse-hl7-v2
                   "MSH|^~\\&|LAB|FAC|||||||P|9.9\rOBX|1|NM|HGB||13.8")))
                "9.9")

  (for ([path (in-list (directory-list fixtures-directory #:build? #t))]
        #:when (regexp-match? #rx"[.]hl7$" (path->string path)))
    (define fixture-source (file->string path))
    (define fixture-report
      (parse-result->report (parse-hl7-v2 fixture-source)))
    (for ([part (in-vector (hl7-report-parts fixture-report))]
          #:when (report-segment? part))
      (for ([field (in-vector (report-segment-visible-fields part #f))])
        (check-false (report-field-empty? field))
        (check-equal? (source-slice fixture-source (report-field-span field))
                      (report-field-raw field))))))
