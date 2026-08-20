#lang racket/base

(require racket/list
         racket/string
         racket/vector
         "model.rkt")

(provide parse-hl7-v2)

(struct raw-segment (start end terminator term-start term-end) #:transparent)
(struct parse-failure (code message position) #:transparent)
(struct separator-declaration (separators msh-2-end) #:transparent)

(define (immutable-vector values)
  (vector->immutable-vector (list->vector values)))

(define (source-slice source start end)
  (string->immutable-string (substring source start end)))

(define (failure code message position)
  (parse-failure code message position))

(define (diagnostic-from-failure problem)
  (hl7-diagnostic (parse-failure-code problem)
                  (parse-failure-message problem)
                  (hl7-span (parse-failure-position problem)
                            (add1 (parse-failure-position problem)))))

(define (terminator-at source position)
  (cond
    [(>= position (string-length source)) #f]
    [(char=? (string-ref source position) #\return)
     (if (and (< (add1 position) (string-length source))
              (char=? (string-ref source (add1 position)) #\newline))
         (cons "\r\n" 2)
         (cons "\r" 1))]
    [(char=? (string-ref source position) #\newline) (cons "\n" 1)]
    [else #f]))

(define (split-message source)
  (define length (string-length source))
  (let loop ([start 0] [position 0] [parts '()])
    (cond
      [(= position length)
       (reverse
        (if (< start length)
            (cons (raw-segment start length #f length length) parts)
            parts))]
      [else
       (define found (terminator-at source position))
       (if found
           (let ([terminator (car found)]
                 [width (cdr found)])
             (loop (+ position width)
                   (+ position width)
                   (cons (raw-segment start
                                      position
                                      terminator
                                      position
                                      (+ position width))
                         parts)))
           (loop start (add1 position) parts))])))

(define (distinct-characters? characters)
  (= (length characters) (length (remove-duplicates characters))))

(define (valid-separator-character? character)
  (and (char? character)
       (let ([code-point (char->integer character)])
         (or (<= 33 code-point 47)
             (<= 58 code-point 64)
             (<= 91 code-point 96)
             (<= 123 code-point 126)))))

(define (valid-separator-characters? characters)
  (and (andmap valid-separator-character? characters)
       (distinct-characters? characters)))

(define (parse-separators source segment)
  (define start (raw-segment-start segment))
  (define end (raw-segment-end segment))
  (cond
    [(< (- end start) 3)
     (failure 'invalid-msh "MSH must contain its three-character name" start)]
    [(not (string=? (substring source start (+ start 3)) "MSH"))
     (failure 'missing-msh "the first segment must be MSH" start)]
    [(< (- end start) 8)
     (failure 'invalid-msh "MSH must contain MSH-1 and four MSH-2 characters" end)]
    [else
     (define mandatory-characters
       (for/list ([position (in-range (+ start 3) (+ start 8))])
         (string-ref source position)))
     (if (valid-separator-characters? mandatory-characters)
         (let* ([separators
                 (hl7-separators (first mandatory-characters)
                                 (second mandatory-characters)
                                 (third mandatory-characters)
                                 (fourth mandatory-characters)
                                 (fifth mandatory-characters))]
                [field-separator (hl7-separators-field separators)]
                [four-character-end (+ start 8)])
           (cond
             [(= end four-character-end)
              (separator-declaration separators four-character-end)]
             [(char=? (string-ref source four-character-end) field-separator)
              (separator-declaration separators four-character-end)]
             [else
              (define truncation-character
                (string-ref source four-character-end))
              (define five-character-end (add1 four-character-end))
              (cond
                [(not (valid-separator-characters?
                       (append mandatory-characters
                               (list truncation-character))))
                 (failure
                  'invalid-separators
                  "MSH separators must be distinct printable ASCII punctuation"
                  four-character-end)]
                [(= end five-character-end)
                 (separator-declaration separators five-character-end)]
                [(char=? (string-ref source five-character-end) field-separator)
                 (separator-declaration separators five-character-end)]
                [else
                 (failure 'invalid-msh
                          "MSH-2 must be followed by the field separator"
                          five-character-end)])]))
         (failure 'invalid-separators
                  "MSH separators must be distinct printable ASCII punctuation"
                  (+ start 3)))]))

(define (split-ranges source start end delimiter escape)
  (let loop ([cursor start] [position start] [ranges '()])
    (cond
      [(= position end)
       (reverse (cons (cons cursor end) ranges))]
      [(char=? (string-ref source position) escape)
       (let find-close ([next (add1 position)])
         (cond
           [(= next end)
            (failure 'unterminated-escape
                     "escape sequence has no closing escape character"
                     position)]
           [(char=? (string-ref source next) escape)
            (loop cursor (add1 next) ranges)]
           [else (find-close (add1 next))]))]
      [(char=? (string-ref source position) delimiter)
       (loop (add1 position)
             (add1 position)
             (cons (cons cursor position) ranges))]
      [else (loop cursor (add1 position) ranges)])))

(define (raw-at source range)
  (source-slice source (car range) (cdr range)))

(define (literal-field source start end)
  (define raw (source-slice source start end))
  (define leaf
    (hl7-subcomponent raw (hl7-span start end)))
  (define component
    (hl7-component raw
                   (immutable-vector (list leaf))
                   (hl7-span start end)))
  (define repetition
    (hl7-repetition raw
                    (immutable-vector (list component))
                    (hl7-span start end)))
  (hl7-field raw
             (immutable-vector (list repetition))
             (hl7-span start end)))

(define (build-component source range separators)
  (define start (car range))
  (define end (cdr range))
  (define ranges
    (split-ranges source
                  start
                  end
                  (hl7-separators-subcomponent separators)
                  (hl7-separators-escape separators)))
  (if (parse-failure? ranges)
      ranges
      (hl7-component
       (raw-at source range)
       (immutable-vector
        (for/list ([subcomponent-range (in-list ranges)])
          (hl7-subcomponent
           (raw-at source subcomponent-range)
           (hl7-span (car subcomponent-range) (cdr subcomponent-range)))))
       (hl7-span start end))))

(define (build-repetition source range separators)
  (define start (car range))
  (define end (cdr range))
  (define ranges
    (split-ranges source
                  start
                  end
                  (hl7-separators-component separators)
                  (hl7-separators-escape separators)))
  (if (parse-failure? ranges)
      ranges
      (let loop ([remaining ranges] [components '()])
        (if (null? remaining)
            (hl7-repetition (raw-at source range)
                            (immutable-vector (reverse components))
                            (hl7-span start end))
            (let ([component (build-component source (car remaining) separators)])
              (if (parse-failure? component)
                  component
                  (loop (cdr remaining) (cons component components))))))))

(define (build-field source range separators)
  (define start (car range))
  (define end (cdr range))
  (define ranges
    (split-ranges source
                  start
                  end
                  (hl7-separators-repetition separators)
                  (hl7-separators-escape separators)))
  (if (parse-failure? ranges)
      ranges
      (let loop ([remaining ranges] [repetitions '()])
        (if (null? remaining)
            (hl7-field (raw-at source range)
                       (immutable-vector (reverse repetitions))
                       (hl7-span start end))
            (let ([repetition (build-repetition source (car remaining) separators)])
              (if (parse-failure? repetition)
                  repetition
                  (loop (cdr remaining) (cons repetition repetitions))))))))

(define (build-fields source ranges separators)
  (let loop ([remaining ranges] [fields '()])
    (if (null? remaining)
        (reverse fields)
        (let ([field (build-field source (car remaining) separators)])
          (if (parse-failure? field)
              field
              (loop (cdr remaining) (cons field fields)))))))

(define (segment-name-valid? name)
  (and (= (string-length name) 3)
       (for/and ([character (in-string name)])
         (or (char<=? #\A character #\Z)
             (char<=? #\0 character #\9)))))

(define (build-msh source segment declaration)
  (define start (raw-segment-start segment))
  (define end (raw-segment-end segment))
  (define separators (separator-declaration-separators declaration))
  (define msh-2-end (separator-declaration-msh-2-end declaration))
  (define field-separator (hl7-separators-field separators))
  (cond
    [(and (> end msh-2-end)
          (not (char=? (string-ref source msh-2-end) field-separator)))
     (failure 'invalid-msh
              "MSH-2 must be followed by the field separator"
              msh-2-end)]
    [else
     (define regular-fields
       (if (= end msh-2-end)
           '()
           (let ([ranges (split-ranges source
                                       (add1 msh-2-end)
                                       end
                                       field-separator
                                       (hl7-separators-escape separators))])
             (if (parse-failure? ranges)
                 ranges
                 (build-fields source ranges separators)))))
     (if (parse-failure? regular-fields)
         regular-fields
         (hl7-segment
          "MSH"
          (source-slice source start end)
          (immutable-vector
           (append
            (list (literal-field source (+ start 3) (+ start 4))
                  (literal-field source (+ start 4) msh-2-end))
            regular-fields))
          (hl7-span start end)))]))

(define (build-segment source segment separators)
  (define start (raw-segment-start segment))
  (define end (raw-segment-end segment))
  (cond
    [(< (- end start) 3)
     (failure 'invalid-segment-name
              "segment names contain exactly three characters"
              start)]
    [else
     (define name (source-slice source start (+ start 3)))
     (cond
       [(not (segment-name-valid? name))
        (failure 'invalid-segment-name
                 "segment name must be three uppercase letters or digits"
                 start)]
       [(and (> (- end start) 3)
             (not (char=? (string-ref source (+ start 3))
                          (hl7-separators-field separators))))
        (failure 'invalid-segment-name
                 "segment name must be followed by the field separator"
                 (+ start 3))]
       [else
        (define fields
          (if (= (- end start) 3)
              '()
              (let ([ranges (split-ranges source
                                          (+ start 4)
                                          end
                                          (hl7-separators-field separators)
                                          (hl7-separators-escape separators))])
                (if (parse-failure? ranges)
                    ranges
                    (build-fields source ranges separators)))))
        (if (parse-failure? fields)
            fields
            (hl7-segment name
                         (source-slice source start end)
                         (immutable-vector fields)
                         (hl7-span start end)))])]))

(define (fatal-result code message position source-length)
  (define end (min (add1 position) source-length))
  (hl7-parse-result
   #f
   (immutable-vector
    (list (hl7-diagnostic code
                          message
                          (hl7-span position end))))
   #f))

(define (parse-remaining source
                         remaining
                         separators
                         expected-terminator
                         first-part
                         initial-diagnostics)
  (let loop ([remaining remaining]
             [parts (list first-part)]
             [diagnostics (reverse initial-diagnostics)])
    (if (null? remaining)
        (values (reverse parts) (reverse diagnostics))
        (let* ([current (car remaining)]
               [term (raw-segment-terminator current)]
               [mixed (and expected-terminator
                            term
                            (not (string=? expected-terminator term)))]
               [mixed-diagnostic
                (if mixed
                    (list
                     (hl7-diagnostic
                      'mixed-segment-terminators
                      "segment terminator differs from the first terminator"
                      (hl7-span (raw-segment-term-start current)
                                (raw-segment-term-end current))))
                    '())]
               [current-start (raw-segment-start current)]
               [current-end (raw-segment-end current)]
               [raw (source-slice source current-start current-end)])
          (if (= current-start current-end)
              (loop (cdr remaining)
                    (cons (hl7-unparsed-segment
                           raw
                           (hl7-span current-start current-end))
                          parts)
                    (append mixed-diagnostic
                            (list
                             (hl7-diagnostic
                              'empty-segment
                              "empty segment between terminators"
                              (hl7-span current-start current-end)))
                            diagnostics))
              (let ([parsed (build-segment source current separators)])
                (if (parse-failure? parsed)
                    (loop (cdr remaining)
                          (cons (hl7-unparsed-segment
                                 raw
                                 (hl7-span current-start current-end))
                                parts)
                          (append mixed-diagnostic
                                  (list (diagnostic-from-failure parsed))
                                  diagnostics))
                    (loop (cdr remaining)
                          (cons parsed parts)
                          (append mixed-diagnostic diagnostics)))))))))

(define (finish-parse source
                      raw-segments
                      separators
                      first-part
                      initial-diagnostics)
  (define expected-terminator
    (for/first ([segment (in-list raw-segments)]
                #:when (raw-segment-terminator segment))
      (raw-segment-terminator segment)))
  (define-values (parts diagnostics)
    (parse-remaining source
                     (cdr raw-segments)
                     separators
                     expected-terminator
                     first-part
                     initial-diagnostics))
  (define message
    (hl7-message source
                 separators
                 expected-terminator
                 (immutable-vector parts)
                 (hl7-span 0 (string-length source))))
  (hl7-parse-result message
                    (immutable-vector diagnostics)
                    (null? diagnostics)))

(define (parse-hl7-v2 text)
  (unless (string? text)
    (raise-argument-error 'parse-hl7-v2 "string?" text))
  (define source (string->immutable-string text))
  (define raw-segments (split-message source))
  (if (null? raw-segments)
      (fatal-result 'empty-input "an HL7 message cannot be empty" 0 0)
      (let ([declaration (parse-separators source (car raw-segments))])
        (if (parse-failure? declaration)
            (fatal-result (parse-failure-code declaration)
                          (parse-failure-message declaration)
                          (parse-failure-position declaration)
                          (string-length source))
            (let* ([separators
                    (separator-declaration-separators declaration)]
                   [msh (build-msh source
                                   (car raw-segments)
                                   declaration)])
              (cond
                [(and (parse-failure? msh)
                      (eq? (parse-failure-code msh) 'unterminated-escape))
                 (define first (car raw-segments))
                 (define first-start (raw-segment-start first))
                 (define first-end (raw-segment-end first))
                 (finish-parse
                  source
                  raw-segments
                  separators
                  (hl7-unparsed-segment
                   (source-slice source first-start first-end)
                   (hl7-span first-start first-end))
                  (list (diagnostic-from-failure msh)))]
                [(parse-failure? msh)
                 (fatal-result (parse-failure-code msh)
                               (parse-failure-message msh)
                               (parse-failure-position msh)
                               (string-length source))]
                [else
                 (finish-parse source
                               raw-segments
                               separators
                               msh
                               '())]))))))
