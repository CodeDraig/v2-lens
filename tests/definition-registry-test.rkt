#lang racket/base

(require rackunit
         "../private/definition-registry.rkt"
         "../private/common-lab-definitions.rkt")

(define common
  (definition-set
   'common-lab #f #f
   (hash "OBX" (segment-definition "Observation Result"
                                    #("Set ID - OBX"
                                      "Value Type"
                                      "Observation Identifier"
                                      "Observation Sub-ID"
                                      "Observation Value")))))

(define v251
  (definition-set
   'test-v251 "2.5.1" "2.5.1"
   (hash "OBX" (segment-definition "Observation/Result"
                                    #(#f #f #f #f
                                      "Versioned Observation Value")))))

(define registry (definition-registry (vector common v251)))

(define v25-range
  (definition-set
   'test-v25-range "2.5" "2.5.9"
   (hash "OBX" (segment-definition "Ranged Observation Result"
                                    #(#f "Ranged Value Type")))))

(define ranged-registry
  (definition-registry (vector common v25-range)))

(define expected-common-field-counts
  (hash "MSH" 21
        "PID" 30
        "PV1" 52
        "ORC" 30
        "OBR" 50
        "OBX" 20
        "NTE" 4
        "SPM" 29))

(define expected-common-field-total
  (for/fold ([total 0])
            ([(segment-name expected-count)
              (in-hash expected-common-field-counts)])
    (+ total expected-count)))

(module+ test
  (check-equal? expected-common-field-total 236)

  (check-equal? (resolve-field-definition registry "OBX" 5 "2.5.1")
                (resolved-definition "Versioned Observation Value"
                                     'version-specific
                                     'test-v251))
  (check-equal? (resolve-field-definition registry "OBX" 3 "2.5.1")
                (resolved-definition
                 "Observation Identifier" 'common 'common-lab))
  (check-equal? (resolve-segment-definition registry "OBX" "2.3")
                (resolved-definition
                 "Observation Result" 'common 'common-lab))
  (check-equal? (resolve-field-definition registry "ZDR" 4 "2.5.1")
                (resolved-definition "Unknown field" 'unknown #f))
  (check-equal? (resolve-segment-definition registry "ZDR" #f)
                (resolved-definition "Unknown segment" 'unknown #f))

  (check-equal? (resolved-definition-provenance
                (resolve-field-definition registry "OBX" 5 "2.5"))
                'common)
  (check-equal? (resolved-definition-provenance
                (resolve-field-definition registry "OBX" 5 "not-a-version"))
                'common)
  (check-equal? (resolved-definition-provenance
                (resolve-field-definition registry "OBX" 5 "2.5e0"))
                'common)
  (check-equal? (resolved-definition-provenance
                (resolve-segment-definition registry "OBX" "9.9.9"))
                'common)

  (check-exn exn:fail:contract?
             (lambda () (resolve-field-definition registry "OBX" 0 #f)))
  (check-exn exn:fail:contract?
             (lambda () (resolve-field-definition registry "OBX" -1 #f)))
  (check-exn exn:fail:contract?
             (lambda () (resolve-field-definition registry "OBX" 1.5 #f)))
  (check-exn exn:fail:contract?
             (lambda () (resolve-segment-definition registry "obx" #f)))
  (check-exn exn:fail:contract?
             (lambda () (resolve-segment-definition registry "OB" #f)))
  (check-exn exn:fail:contract?
             (lambda () (resolve-segment-definition registry "OBX" 2.5)))

  (check-equal? (resolve-field-definition registry "OBX" 6 #f)
                (resolved-definition "Unknown field" 'unknown #f))
  (check-equal? (resolve-field-definition registry "OBX" 5 #f)
                (resolved-definition "Observation Value" 'common 'common-lab))

  (check-equal? (resolve-segment-definition ranged-registry "OBX" "2.5.1")
                (resolved-definition "Ranged Observation Result"
                                     'version-specific
                                     'test-v25-range))
  (check-equal? (resolve-field-definition ranged-registry "OBX" 2 "2.5.1")
                (resolved-definition "Ranged Value Type"
                                     'version-specific
                                     'test-v25-range))
  (check-equal? (resolved-definition-provenance
                (resolve-field-definition ranged-registry "OBX" 2 "2.6"))
                'common)

  (for ([(segment-name expected-count)
         (in-hash expected-common-field-counts)])
    (check-not-equal?
     (resolved-definition-provenance
      (resolve-segment-definition common-lab-registry segment-name "2.5.1"))
     'unknown)
    (for ([position (in-range 1 (add1 expected-count))])
      (check-not-equal?
       (resolved-definition-provenance
        (resolve-field-definition
         common-lab-registry segment-name position "2.5.1"))
       'unknown
       (format "~a-~a" segment-name position))))

  (check-equal?
   (resolved-definition-label
    (resolve-field-definition common-lab-registry "MSH" 12 "2.3"))
   "Version ID")
  (check-equal?
   (resolved-definition-label
    (resolve-field-definition common-lab-registry "OBR" 4 "2.3"))
   "Universal Service Identifier")
  (check-equal?
   (resolved-definition-label
    (resolve-field-definition common-lab-registry "OBX" 5 "2.3"))
   "Observation Value")
  (check-equal?
   (resolved-definition-label
    (resolve-field-definition common-lab-registry "SPM" 4 "2.5.1"))
   "Specimen Type")

  (for ([(segment-name expected-count)
         (in-hash expected-common-field-counts)])
    (check-equal?
     (resolve-field-definition
      common-lab-registry segment-name (add1 expected-count) "2.5.1")
     (resolved-definition "Unknown field" 'unknown #f)
     (format "~a out-of-range" segment-name)))
  (check-equal?
   (resolve-segment-definition common-lab-registry "ZDR" "2.5.1")
   (resolved-definition "Unknown segment" 'unknown #f)))
