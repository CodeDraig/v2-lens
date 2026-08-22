#lang racket/base

(require racket/list
         racket/string)

(provide max-parse-bytes
         max-open-file-bytes
         max-structural-delimiters
         report-part-batch-size
         report-field-batch-size
         diagnostic-batch-size
         large-report-part-count
         max-field-control-label-length
         source-utf-8-size
         source-structural-delimiter-count
         source-parse-refusal
         file-open-refusal
         bounded-control-label)

(define max-parse-bytes (* 5 1024 1024))
(define max-open-file-bytes (* 100 1024 1024))
(define max-structural-delimiters 50000)
(define report-part-batch-size 100)
(define report-field-batch-size 100)
(define diagnostic-batch-size 250)
(define large-report-part-count 50)
(define max-field-control-label-length 200)

(define (source-utf-8-size source)
  (unless (string? source)
    (raise-argument-error 'source-utf-8-size "string?" source))
  (string-utf-8-length source))

(define (declared-structural-characters source)
  (define length (string-length source))
  (define declared
    (if (and (>= length 8)
             (string=? (substring source 0 3) "MSH"))
        (for/list ([position (in-range 3 8)])
          (string-ref source position))
        '()))
  (remove-duplicates (append declared (list #\return #\newline))))

(define (source-structural-delimiter-count source)
  (unless (string? source)
    (raise-argument-error
     'source-structural-delimiter-count "string?" source))
  (define structural-characters (declared-structural-characters source))
  (for/sum ([character (in-string source)]
            #:when (memv character structural-characters))
    1))

(define (source-parse-refusal source)
  (unless (string? source)
    (raise-argument-error 'source-parse-refusal "string?" source))
  (define byte-count (source-utf-8-size source))
  (cond
    [(> byte-count max-parse-bytes)
     (format
      "Raw only — ~a UTF-8 bytes exceeds the 5 MiB public beta parse limit"
      byte-count)]
    [else
     (define delimiter-count (source-structural-delimiter-count source))
     (and (> delimiter-count max-structural-delimiters)
          (format
           (string-append
            "Raw only — ~a structural delimiters exceeds the public beta "
            "limit of ~a")
           delimiter-count
           max-structural-delimiters))]))

(define (file-open-refusal path)
  (unless (path-string? path)
    (raise-argument-error 'file-open-refusal "path-string?" path))
  (define byte-count (file-size path))
  (and (> byte-count max-open-file-bytes)
       (format
        "Cannot open file — ~a bytes exceeds the 100 MiB public beta limit"
        byte-count)))

(define (printable-control-character? character)
  (or (char=? character #\tab)
      (not (char-iso-control? character))))

(define (bounded-control-label label [limit max-field-control-label-length])
  (unless (string? label)
    (raise-argument-error 'bounded-control-label "string?" label))
  (unless (exact-positive-integer? limit)
    (raise-argument-error
     'bounded-control-label "exact-positive-integer?" limit))
  (define safe
    (list->string
     (for/list ([character (in-string label)])
       (if (printable-control-character? character) character #\uFFFD))))
  (cond
    [(<= (string-length safe) limit) safe]
    [(= limit 1) "…"]
    [else (string-append (substring safe 0 (sub1 limit)) "…")]))
