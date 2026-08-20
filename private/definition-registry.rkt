#lang racket/base

(require racket/list
         racket/string)

(provide (struct-out segment-definition)
         (struct-out definition-set)
         (struct-out definition-registry)
         (struct-out resolved-definition)
         resolve-segment-definition
         resolve-field-definition)

(struct segment-definition (label fields) #:transparent)
(struct definition-set
  (identifier minimum-version maximum-version segments)
  #:transparent)
(struct definition-registry (sets) #:transparent)
(struct resolved-definition (label provenance source-identifier) #:transparent)

(define (version-key version)
  (and version
       (let ([pieces (string-split version ".")])
         (and (andmap (lambda (piece)
                        (regexp-match? #px"^[0-9]+$" piece))
                      pieces)
              (map string->number pieces)))))

(define (compare-version-keys left right)
  (let loop ([left left] [right right])
    (cond
      [(and (null? left) (null? right)) 0]
      [(null? left) (loop '(0) right)]
      [(null? right) (loop left '(0))]
      [(< (car left) (car right)) -1]
      [(> (car left) (car right)) 1]
      [else (loop (cdr left) (cdr right))])))

(define (specific-set-matches? set version)
  (define candidate (version-key version))
  (define minimum (version-key (definition-set-minimum-version set)))
  (define maximum (version-key (definition-set-maximum-version set)))
  (and candidate minimum maximum
       (<= (compare-version-keys minimum candidate) 0)
       (<= (compare-version-keys candidate maximum) 0)))

(define (common-set? set)
  (and (not (definition-set-minimum-version set))
       (not (definition-set-maximum-version set))))

(define (ordered-sets registry version)
  (append
   (for/list ([set (in-vector (definition-registry-sets registry))]
              #:when (specific-set-matches? set version))
     (cons set 'version-specific))
   (for/list ([set (in-vector (definition-registry-sets registry))]
              #:when (common-set? set))
     (cons set 'common))))

(define (check-resolution-arguments who registry segment-name
                                    [position #f] [version #f])
  (unless (definition-registry? registry)
    (raise-argument-error who "definition-registry?" registry))
  (unless (and (string? segment-name)
               (regexp-match? #px"^[A-Z0-9]{3}$" segment-name))
    (raise-argument-error
     who "three-character uppercase alphanumeric segment name" segment-name))
  (when (and position (not (exact-positive-integer? position)))
    (raise-argument-error who "exact-positive-integer?" position))
  (unless (or (not version) (string? version))
    (raise-argument-error who "(or/c string? #f)" version)))

(define (resolve-segment-definition registry segment-name [version #f])
  (check-resolution-arguments
   'resolve-segment-definition registry segment-name #f version)
  (or (for/or ([entry (in-list (ordered-sets registry version))])
        (define segment
          (hash-ref (definition-set-segments (car entry)) segment-name #f))
        (and segment
             (resolved-definition (segment-definition-label segment)
                                  (cdr entry)
                                  (definition-set-identifier (car entry)))))
      (resolved-definition "Unknown segment" 'unknown #f)))

(define (resolve-field-definition registry segment-name position [version #f])
  (check-resolution-arguments
   'resolve-field-definition registry segment-name position version)
  (or (for/or ([entry (in-list (ordered-sets registry version))])
        (define segment
          (hash-ref (definition-set-segments (car entry)) segment-name #f))
        (and segment
             (<= position (vector-length (segment-definition-fields segment)))
             (vector-ref (segment-definition-fields segment) (sub1 position))
             (resolved-definition
              (vector-ref (segment-definition-fields segment) (sub1 position))
              (cdr entry)
              (definition-set-identifier (car entry)))))
      (resolved-definition "Unknown field" 'unknown #f)))
