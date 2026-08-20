#lang racket/base

(require racket/match
         racket/vector)

(provide (struct-out hl7-span)
         (struct-out hl7-separators)
         (struct-out hl7-parse-result)
         (struct-out hl7-diagnostic)
         (struct-out hl7-message)
         (struct-out hl7-segment)
         (struct-out hl7-unparsed-segment)
         (struct-out hl7-field)
         (struct-out hl7-repetition)
         (struct-out hl7-component)
         (struct-out hl7-subcomponent)
         hl7-message-segments
         hl7-message-unparsed-parts
         hl7-message-segment
         hl7-segment-field
         hl7-field-repetition
         hl7-repetition-component
         hl7-component-subcomponent
         hl7-node-raw
         hl7-node-span)

(struct hl7-span (start end) #:transparent)
(struct hl7-separators (field component repetition escape subcomponent)
  #:transparent)
(struct hl7-parse-result (message diagnostics complete?) #:transparent)
(struct hl7-diagnostic (code message span) #:transparent)
(struct hl7-message (source separators terminator parts span) #:transparent)
(struct hl7-segment (name raw fields span) #:transparent)
(struct hl7-unparsed-segment (raw span) #:transparent)
(struct hl7-field (raw repetitions span) #:transparent)
(struct hl7-repetition (raw components span) #:transparent)
(struct hl7-component (raw subcomponents span) #:transparent)
(struct hl7-subcomponent (raw span) #:transparent)

(define (immutable-vector values)
  (vector->immutable-vector (list->vector values)))

(define (positive-index who value)
  (unless (exact-positive-integer? value)
    (raise-argument-error who "exact-positive-integer?" value)))

(define (vector-ref/1 who values index)
  (positive-index who index)
  (and (<= index (vector-length values))
       (vector-ref values (sub1 index))))

(define (valid-segment-name? name)
  (and (= (string-length name) 3)
       (for/and ([character (in-string name)])
         (or (char<=? #\A character #\Z)
             (char<=? #\0 character #\9)))))

(define (hl7-message-segments message)
  (unless (hl7-message? message)
    (raise-argument-error 'hl7-message-segments "hl7-message?" message))
  (immutable-vector
   (for/list ([part (in-vector (hl7-message-parts message))]
              #:when (hl7-segment? part))
     part)))

(define (hl7-message-unparsed-parts message)
  (unless (hl7-message? message)
    (raise-argument-error 'hl7-message-unparsed-parts "hl7-message?" message))
  (immutable-vector
   (for/list ([part (in-vector (hl7-message-parts message))]
              #:when (hl7-unparsed-segment? part))
     part)))

(define (hl7-message-segment message name [occurrence 1])
  (unless (hl7-message? message)
    (raise-argument-error 'hl7-message-segment "hl7-message?" message))
  (unless (string? name)
    (raise-argument-error 'hl7-message-segment "string?" name))
  (unless (valid-segment-name? name)
    (raise-argument-error 'hl7-message-segment
                          "three-character uppercase alphanumeric segment name"
                          name))
  (positive-index 'hl7-message-segment occurrence)
  (let loop ([parts (vector->list (hl7-message-parts message))]
             [remaining occurrence])
    (cond
      [(null? parts) #f]
      [(and (hl7-segment? (car parts))
            (string=? name (hl7-segment-name (car parts))))
       (if (= remaining 1)
           (car parts)
           (loop (cdr parts) (sub1 remaining)))]
      [else (loop (cdr parts) remaining)])))

(define (hl7-segment-field segment index)
  (unless (hl7-segment? segment)
    (raise-argument-error 'hl7-segment-field "hl7-segment?" segment))
  (vector-ref/1 'hl7-segment-field (hl7-segment-fields segment) index))

(define (hl7-field-repetition field index)
  (unless (hl7-field? field)
    (raise-argument-error 'hl7-field-repetition "hl7-field?" field))
  (vector-ref/1 'hl7-field-repetition (hl7-field-repetitions field) index))

(define (hl7-repetition-component repetition index)
  (unless (hl7-repetition? repetition)
    (raise-argument-error 'hl7-repetition-component "hl7-repetition?" repetition))
  (vector-ref/1 'hl7-repetition-component
                (hl7-repetition-components repetition)
                index))

(define (hl7-component-subcomponent component index)
  (unless (hl7-component? component)
    (raise-argument-error 'hl7-component-subcomponent "hl7-component?" component))
  (vector-ref/1 'hl7-component-subcomponent
                (hl7-component-subcomponents component)
                index))

(define (hl7-node-raw node)
  (match node
    [(hl7-message source _ _ _ _) source]
    [(hl7-segment _ raw _ _) raw]
    [(hl7-unparsed-segment raw _) raw]
    [(hl7-field raw _ _) raw]
    [(hl7-repetition raw _ _) raw]
    [(hl7-component raw _ _) raw]
    [(hl7-subcomponent raw _) raw]
    [_ (raise-argument-error 'hl7-node-raw "hl7-node?" node)]))

(define (hl7-node-span node)
  (match node
    [(hl7-message _ _ _ _ span) span]
    [(hl7-segment _ _ _ span) span]
    [(hl7-unparsed-segment _ span) span]
    [(hl7-field _ _ span) span]
    [(hl7-repetition _ _ span) span]
    [(hl7-component _ _ span) span]
    [(hl7-subcomponent _ span) span]
    [_ (raise-argument-error 'hl7-node-span "hl7-node?" node)]))
