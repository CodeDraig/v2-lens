#lang racket/base

(require racket/file
         racket/list
         racket/match
         racket/runtime-path
         rackunit
         "../main.rkt")

(define-runtime-path fixtures-directory "fixtures")

(define (fixture name)
  (file->string (build-path fixtures-directory name)))

(define expected-fixture-segments
  (hash "sample_adt_a01.hl7" 11
        "sample_adt_a01_encoded.hl7" 2
        "sample_adt_a02.hl7" 4
        "sample_adt_a03.hl7" 4
        "sample_adt_a04.hl7" 15
        "sample_adt_a08.hl7" 12
        "sample_oru_r01_generic.hl7" 19
        "sample_oru_r01_lab.hl7" 21))

(define (clean-message result)
  (check-true (hl7-parse-result? result))
  (check-true (hl7-parse-result-complete? result))
  (check-equal? (vector-length (hl7-parse-result-diagnostics result)) 0)
  (define message (hl7-parse-result-message result))
  (check-true (hl7-message? message))
  message)

(define (assert-spans source node)
  (define span (hl7-node-span node))
  (check-true (immutable? (hl7-node-raw node)))
  (check-true (<= 0 (hl7-span-start span)))
  (check-true (<= (hl7-span-start span) (hl7-span-end span)))
  (check-true (<= (hl7-span-end span) (string-length source)))
  (check-equal? (substring source
                            (hl7-span-start span)
                            (hl7-span-end span))
                (hl7-node-raw node))
  (match node
    [(hl7-message _ _ _ parts _)
     (for ([part (in-vector parts)])
       (assert-spans source part))]
    [(hl7-segment name _ fields _)
     (check-true (immutable? name))
     (for ([field (in-vector fields)])
       (assert-spans source field))]
    [(hl7-unparsed-segment _ _) (void)]
    [(hl7-field _ repetitions _)
     (for ([repetition (in-vector repetitions)])
       (assert-spans source repetition))]
    [(hl7-repetition _ components _)
     (for ([component (in-vector components)])
       (assert-spans source component))]
    [(hl7-component _ subcomponents _)
     (for ([subcomponent (in-vector subcomponents)])
       (assert-spans source subcomponent))]
    [(hl7-subcomponent _ _) (void)]))

(module+ test
  (for ([(name expected-count) (in-hash expected-fixture-segments)])
    (define source (fixture name))
    (define message (clean-message (parse-hl7-v2 source)))
    (check-equal? (vector-length (hl7-message-segments message)) expected-count name)
    (assert-spans source message))

  (define encoded-message
    (clean-message (parse-hl7-v2 (fixture "sample_adt_a01_encoded.hl7"))))
  (define encoded-msh (hl7-message-segment encoded-message "MSH"))
  (check-equal? (hl7-node-raw (hl7-segment-field encoded-msh 5)) "Isaac\\S\\2")

  (define hierarchy-source "MSH|^~\\&|\rPID|one~two^three&four||")
  (define hierarchy-message (clean-message (parse-hl7-v2 hierarchy-source)))
  (define hierarchy-msh (hl7-message-segment hierarchy-message "MSH"))
  (check-equal? (hl7-node-raw (hl7-segment-field hierarchy-msh 1)) "|")
  (check-equal? (hl7-node-raw (hl7-segment-field hierarchy-msh 2)) "^~\\&")
  (define hierarchy-field
    (hl7-segment-field (hl7-message-segment hierarchy-message "PID") 1))
  (check-equal? (vector-length (hl7-field-repetitions hierarchy-field)) 2)
  (define hierarchy-component
    (hl7-repetition-component (hl7-field-repetition hierarchy-field 2) 2))
  (check-equal? (vector-length (hl7-component-subcomponents hierarchy-component)) 2)
  (check-equal? (hl7-node-raw
                 (hl7-component-subcomponent hierarchy-component 2))
                "four")
  (check-equal? (vector-length
                 (hl7-segment-fields (hl7-message-segment hierarchy-message "PID")))
                3)
  (check-equal? (hl7-node-raw
                 (hl7-segment-field (hl7-message-segment hierarchy-message "PID") 3))
                "")

  (define custom-source "MSH*$%!?*APP\rPID*alpha!Zfoo*bar!beta")
  (define custom-message (clean-message (parse-hl7-v2 custom-source)))
  (define custom-separators (hl7-message-separators custom-message))
  (check-equal? (hl7-separators-field custom-separators) #\*)
  (check-equal? (hl7-separators-component custom-separators) #\$)
  (check-equal? (hl7-separators-repetition custom-separators) #\%)
  (check-equal? (hl7-separators-escape custom-separators) #\!)
  (check-equal? (hl7-node-raw
                 (hl7-segment-field (hl7-message-segment custom-message "PID") 1))
                "alpha!Zfoo*bar!beta")

  (define truncation-source "MSH|^~\\&#|APP|FAC\rPID|1")
  (define truncation-message
    (clean-message (parse-hl7-v2 truncation-source)))
  (define truncation-msh
    (hl7-message-segment truncation-message "MSH"))
  (check-equal? (hl7-node-raw (hl7-segment-field truncation-msh 1)) "|")
  (check-equal? (hl7-node-raw (hl7-segment-field truncation-msh 2))
                "^~\\&#")
  (check-equal? (hl7-node-raw (hl7-segment-field truncation-msh 3)) "APP")
  (check-equal? (hl7-node-raw (hl7-segment-field truncation-msh 4)) "FAC")
  (check-equal? (hl7-node-raw
                 (hl7-segment-field
                  (hl7-message-segment truncation-message "PID")
                  1))
                "1")
  (check-equal? (hl7-separators-subcomponent
                 (hl7-message-separators truncation-message))
                #\&)
  (assert-spans truncation-source truncation-message)

  (define custom-truncation-source "MSH*$%!?+*APP\rPID*1")
  (define custom-truncation-message
    (clean-message (parse-hl7-v2 custom-truncation-source)))
  (define custom-truncation-msh
    (hl7-message-segment custom-truncation-message "MSH"))
  (check-equal? (hl7-node-raw
                 (hl7-segment-field custom-truncation-msh 2))
                "$%!?+")
  (check-equal? (hl7-node-raw
                 (hl7-segment-field custom-truncation-msh 3))
                "APP")
  (assert-spans custom-truncation-source custom-truncation-message)

  (define truncation-only-source "MSH|^~\\&#")
  (define truncation-only-message
    (clean-message (parse-hl7-v2 truncation-only-source)))
  (define truncation-only-msh
    (hl7-message-segment truncation-only-message "MSH"))
  (check-equal? (vector-length (hl7-segment-fields truncation-only-msh)) 2)
  (check-equal? (hl7-node-raw
                 (hl7-segment-field truncation-only-msh 2))
                "^~\\&#")
  (assert-spans truncation-only-source truncation-only-message)

  (define invalid-separator-inputs
    (list "MSH12345"
          "MSH|ABCD"
          "MSH|^~\\ "
          (string-append "MSH|^~\\" (string #\nul))
          (string-append "MSH|^~\\" (string (integer->char 127)))
          "MSH|^~\\雪"
          "MSH|^~\\&^|APP"
          "MSH|^~\\&A|APP"))
  (for ([input (in-list invalid-separator-inputs)])
    (define result (parse-hl7-v2 input))
    (check-false (hl7-parse-result-message result) input)
    (check-false (hl7-parse-result-complete? result) input)
    (check-equal? (vector-length (hl7-parse-result-diagnostics result)) 1 input)
    (check-equal? (hl7-diagnostic-code
                   (vector-ref (hl7-parse-result-diagnostics result) 0))
                  'invalid-separators
                  input))

  (define missing-truncation-boundary-result
    (parse-hl7-v2 "MSH|^~\\&#APP"))
  (check-false
   (hl7-parse-result-message missing-truncation-boundary-result))
  (check-equal?
   (hl7-diagnostic-code
    (vector-ref
     (hl7-parse-result-diagnostics missing-truncation-boundary-result)
     0))
   'invalid-msh)

  (for ([terminator '("\r" "\n" "\r\n")])
    (define message
      (clean-message
       (parse-hl7-v2
        (string-append "MSH|^~\\&|APP" terminator "PID|1"))))
    (check-equal? (hl7-message-terminator message) terminator))

  (define mixed-result
    (parse-hl7-v2 "MSH|^~\\&|APP\r\nPID|1\nOBX|2"))
  (check-not-false (hl7-parse-result-message mixed-result))
  (check-false (hl7-parse-result-complete? mixed-result))
  (check-equal? (vector-length (hl7-message-segments
                                (hl7-parse-result-message mixed-result)))
                3)
  (check-equal? (hl7-diagnostic-code
                 (vector-ref (hl7-parse-result-diagnostics mixed-result) 0))
                'mixed-segment-terminators)

  (define recovery-source
    "MSH|^~\\&|APP\rBAD!oops\rPID|1\rOBX|bad\\F\rZXX|ok")
  (define recovery-result (parse-hl7-v2 recovery-source))
  (check-false (hl7-parse-result-complete? recovery-result))
  (define recovery-message (hl7-parse-result-message recovery-result))
  (check-equal? (vector-length (hl7-message-segments recovery-message)) 3)
  (check-equal? (vector-length (hl7-message-unparsed-parts recovery-message)) 2)
  (check-equal? (hl7-diagnostic-code
                 (vector-ref (hl7-parse-result-diagnostics recovery-result) 0))
                'invalid-segment-name)
  (check-equal? (hl7-diagnostic-code
                 (vector-ref (hl7-parse-result-diagnostics recovery-result) 1))
                'unterminated-escape)
  (check-equal? (hl7-segment-name
                 (hl7-message-segment recovery-message "ZXX"))
                "ZXX")
  (assert-spans recovery-source recovery-message)

  (define msh-recovery-source "MSH|^~\\&|bad\\F\rPID|1")
  (define msh-recovery-result (parse-hl7-v2 msh-recovery-source))
  (check-false (hl7-parse-result-complete? msh-recovery-result))
  (define msh-recovery-message
    (hl7-parse-result-message msh-recovery-result))
  (check-true (hl7-message? msh-recovery-message))
  (check-equal? (vector-length
                 (hl7-message-unparsed-parts msh-recovery-message))
                1)
  (check-equal? (hl7-node-raw
                 (vector-ref (hl7-message-parts msh-recovery-message) 0))
                "MSH|^~\\&|bad\\F")
  (check-equal? (hl7-diagnostic-code
                 (vector-ref
                  (hl7-parse-result-diagnostics msh-recovery-result)
                  0))
                'unterminated-escape)
  (check-equal? (hl7-node-raw
                 (hl7-segment-field
                  (hl7-message-segment msh-recovery-message "PID")
                  1))
                "1")
  (assert-spans msh-recovery-source msh-recovery-message)

  (define empty-result (parse-hl7-v2 ""))
  (check-false (hl7-parse-result-message empty-result))
  (check-equal? (hl7-diagnostic-code
                 (vector-ref (hl7-parse-result-diagnostics empty-result) 0))
                'empty-input)
  (for ([input '("PID|1" "MSH|^" "MSH||~\\&|" "MSH|^~\\\rBAD")]
        [expected '(missing-msh invalid-msh invalid-separators invalid-msh)])
    (define result (parse-hl7-v2 input))
    (check-false (hl7-parse-result-message result))
    (check-equal? (hl7-diagnostic-code
                   (vector-ref (hl7-parse-result-diagnostics result) 0))
                  expected))

  (define unicode-source "MSH|^~\\&|\nPID|λ雪")
  (define unicode-message (clean-message (parse-hl7-v2 unicode-source)))
  (define unicode-leaf
    (hl7-segment-field (hl7-message-segment unicode-message "PID") 1))
  (check-equal? (hl7-node-raw unicode-leaf) "λ雪")
  (check-equal? (hl7-span-start (hl7-node-span unicode-leaf)) 14)
  (check-equal? (hl7-span-end (hl7-node-span unicode-leaf)) 16)

  (define mutable-source (string-copy "MSH|^~\\&|APP"))
  (define immutable-result (parse-hl7-v2 mutable-source))
  (string-set! mutable-source 0 #\X)
  (check-equal? (hl7-message-source (hl7-parse-result-message immutable-result))
                "MSH|^~\\&|APP")

  (define immutable-pid
    (hl7-message-segment hierarchy-message "PID"))
  (define immutable-field (hl7-segment-field immutable-pid 1))
  (check-exn exn:fail:contract?
             (lambda ()
               (string-set! (hl7-segment-name immutable-pid) 0 #\X)))
  (check-exn exn:fail:contract?
             (lambda ()
               (string-set! (hl7-node-raw immutable-field) 0 #\X)))
  (check-eq? (hl7-message-segment hierarchy-message "PID") immutable-pid)
  (check-equal? (hl7-node-raw immutable-field)
                (substring hierarchy-source
                           (hl7-span-start (hl7-node-span immutable-field))
                           (hl7-span-end (hl7-node-span immutable-field))))

  (check-false (hl7-message-segment hierarchy-message "PID" 2))
  (check-false (hl7-segment-field hierarchy-msh 99))
  (check-exn exn:fail:contract?
             (lambda () (hl7-segment-field hierarchy-msh 0)))
  (check-exn exn:fail:contract?
             (lambda () (hl7-message-segment hierarchy-message "pid")))
  (check-exn exn:fail:contract?
             (lambda () (parse-hl7-v2 42))))
