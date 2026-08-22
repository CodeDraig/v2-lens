#lang racket/base

(require racket/class
         racket/file
         racket/gui/base
         racket/match
         racket/path
         (only-in framework text:basic%)
         "main.rkt"
         "private/desktop-guardrails.rkt"
         "private/gui-model.rkt"
         "private/report-model.rkt")

(provide run-v2-lens)

(define (source->display source [build-position-map? #t])
  (cond
    [(not build-position-map?)
     (values (regexp-replace* #rx"\r\n?" source "\n") #f)]
    [else
     (define source-length (string-length source))
     (define positions (make-vector (add1 source-length) 0))
     (define output (open-output-string))
     (define (record-position! source-position display-position)
       (vector-set! positions source-position display-position))
     (let loop ([source-position 0]
                [display-position 0])
       (record-position! source-position display-position)
       (cond
         [(= source-position source-length)
          (define display (get-output-string output))
          (close-output-port output)
          (values display positions)]
         [(char=? (string-ref source source-position) #\return)
          (define next-position (add1 source-position))
          (write-char #\newline output)
          (if (and (< next-position source-length)
                   (char=? (string-ref source next-position) #\newline))
              (begin
                (record-position! next-position (add1 display-position))
                (loop (add1 next-position)
                      (add1 display-position)))
              (loop next-position
                    (add1 display-position)))]
         [else
          (write-char (string-ref source source-position) output)
          (loop (add1 source-position)
                (add1 display-position))]))]))

(define source-text%
  (class text:basic%
    (init-field changed-callback)
    (super-new [auto-wrap #f])

    (define suppress-change? #f)

    (define/public (replace-contents text)
      (unless (string? text)
        (raise-argument-error 'replace-contents "string?" text))
      (dynamic-wind
       (lambda ()
         (set! suppress-change? #t)
         (send this begin-edit-sequence))
       (lambda ()
         (send this erase)
         (send this insert text)
         (send this change-style
               (make-object style-delta% 'change-family 'modern)
               0
               'end)
         (send this set-position 0 0 #f #f 'local))
       (lambda ()
         (send this end-edit-sequence)
         (set! suppress-change? #f))))

    (define/augment (after-insert start length)
      (inner (void) after-insert start length)
      (unless suppress-change?
        (changed-callback)))

    (define/augment (after-delete start length)
      (inner (void) after-delete start length)
      (unless suppress-change?
        (changed-callback)))))

(struct card-controls (card header fields-panel field-controls segment)
  #:transparent)

(struct field-control (control label) #:transparent)

(define inspector-frame%
  (class frame%
    (init-field [parser parse-hl7-v2]
                [report-builder parse-result->report])
    (super-new [label "V2 Lens — Public Beta"] [width 1100] [height 700])

    (define current-display-name #f)
    (define current-result #f)
    (define current-report #f)
    (define active-view 'raw)
    (define exact-source #f)
    (define source-position-map #f)
    (define show-empty-fields? #f)
    (define report-transitioning? #f)
    (define pending-show-empty-value #f)
    (define card-controls-by-path (make-hash))
    (define card-expanded-by-path (make-hash))
    (define selected-card-path #f)
    (define selected-report-field #f)
    (define rendered-part-limit report-part-batch-size)
    (define diagnostic-limit diagnostic-batch-size)
    (define current-diagnostics #())
    (define field-limit-by-path (make-hash))
    (define default-card-expanded? #t)
    (define operation-generation 0)
    (define operation-custodian #f)
    (define operation-active? #f)

    (define root-panel
      (new vertical-panel%
           [parent this]
           [alignment '(left top)]
           [spacing 8]
           [border 8]))
    (define toolbar
      (new horizontal-panel%
           [parent root-panel]
           [alignment '(left center)]
           [stretchable-height #f]
           [spacing 8]))
    (define current-file-message
      (new message%
           [parent toolbar]
           [label "Untitled"]
           [stretchable-width #t]))
    (define status-message
      (new message%
           [parent toolbar]
           [label "Paste or open an HL7 v2 message"]
           [stretchable-width #t]))

    (define source-editor
      (new source-text%
           [changed-callback (lambda () (source-changed!))]))

    (define menu-bar
      (new menu-bar% [parent this]))
    (define edit-menu
      (new menu% [label "&Edit"] [parent menu-bar]))
    (append-editor-operation-menu-items edit-menu)

    (define view-tabs
      (new tab-panel%
           [parent root-panel]
           [choices '("Readable" "Raw Source")]
           [callback
            (lambda (tabs _event)
              (select-view! (if (zero? (send tabs get-selection))
                                'readable
                                'raw)))]
           [stretchable-width #t]
           [stretchable-height #t]))
    (define readable-panel
      (new vertical-panel%
           [parent view-tabs]
           [style '(auto-vscroll)]
           [alignment '(left top)]
           [spacing 8]
           [border 8]
           [stretchable-width #t]
           [stretchable-height #t]))
    (define interpretation-message
      (new message%
           [parent readable-panel]
           [label ""]
           [stretchable-width #t]))
    (define report-actions
      (new horizontal-panel%
           [parent readable-panel]
           [alignment '(left center)]
           [spacing 8]
           [stretchable-width #t]
           [stretchable-height #f]))
    (define show-empty-control
      (new check-box%
           [parent report-actions]
           [label "Show empty fields"]
           [value #f]
           [callback
            (lambda (control _event)
              (request-show-empty-fields! (send control get-value)))]))
    (define report-transition-message
      (new message%
           [parent report-actions]
           [label ""]
           [auto-resize #t]))
    (define expand-all-button
      (new button%
           [parent report-actions]
           [label "Expand Loaded"]
           [callback (lambda (_button _event) (set-all-cards-expanded! #t))]))
    (define collapse-all-button
      (new button%
           [parent report-actions]
           [label "Collapse Loaded"]
           [callback (lambda (_button _event) (set-all-cards-expanded! #f))]))
    (define load-more-parts-button
      (new button%
           [parent report-actions]
           [label "Load More Segments"]
           [callback (lambda (_button _event) (load-more-report-parts!))]))
    (define report-cards-panel
      (new vertical-panel%
           [parent readable-panel]
           [alignment '(left top)]
           [spacing 8]
           [stretchable-width #t]
           [stretchable-height #f]))
    (define raw-panel
      (new vertical-panel%
           [parent view-tabs]
           [alignment '(left top)]
           [stretchable-width #t]
           [stretchable-height #t]))
    (define back-to-report-button
      (new button%
           [parent raw-panel]
           [label "Back to Report"]
           [callback (lambda (_button _event) (show-report!))]
           [stretchable-height #f]))
    (define source-canvas
      (new editor-canvas%
           [parent raw-panel]
           [editor source-editor]
           [style '(auto-hscroll auto-vscroll control-border)]
           [stretchable-width #t]
           [stretchable-height #t]))

    (define diagnostics-list
      (new list-box%
           [parent root-panel]
           [label "Diagnostics"]
           [choices '()]
           [style '(single)]
           [min-height 130]
           [stretchable-height #f]
           [callback
            (lambda (control _event)
              (define selection (send control get-selection))
              (when selection
                (show-raw-span! (send control get-data selection))))]))
    (define load-more-diagnostics-button
      (new button%
           [parent root-panel]
           [label "Load More Diagnostics"]
           [callback (lambda (_button _event) (load-more-diagnostics!))]
           [stretchable-height #f]))

    (define open-button
      (new button%
           [parent toolbar]
           [label "Open…"]
           [callback (lambda (_button _event) (open-file!))]))
    (define parse-button
      (new button%
           [parent toolbar]
           [label "Parse"]
           [callback (lambda (_button _event) (request-parse!))]))

    (send report-transition-message show #f)
    (send load-more-parts-button show #f)
    (send load-more-diagnostics-button show #f)

    (define/private (set-current-file-label! modified?)
      (send current-file-message
            set-label
            (cond
              [current-display-name
               (if modified?
                   (format "~a (modified)" current-display-name)
                   current-display-name)]
              [else "Untitled"])))

    (define/private (set-operation-active! active?)
      (set! operation-active? active?)
      (send open-button enable (not active?))
      (send parse-button enable (not active?)))

    (define/private (cancel-operation!)
      (set! operation-generation (add1 operation-generation))
      (when operation-custodian
        (custodian-shutdown-all operation-custodian))
      (set! operation-custodian #f)
      (set-operation-active! #f))

    (define/private (start-operation! working-label work success failure-label)
      (cancel-operation!)
      (define token operation-generation)
      (define custodian (make-custodian))
      (set! operation-custodian custodian)
      (set-operation-active! #t)
      (send status-message set-label working-label)
      (parameterize ([current-custodian custodian])
        (thread
         (lambda ()
           (define outcome
             (with-handlers ([exn:fail? (lambda (_problem) '(failure))])
               (list 'success (work))))
           (queue-callback
            (lambda ()
              (when (= token operation-generation)
                (set! operation-custodian #f)
                (set-operation-active! #f)
                (match outcome
                  [(list 'success value)
                   (with-handlers
                       ([exn:fail?
                         (lambda (_problem)
                           (clear-results!)
                           (send status-message set-label failure-label))])
                     (success value))]
                  [_
                   (clear-results!)
                   (send status-message set-label failure-label)])))
            #f))))
      token)

    (define/public (select-view! view)
      (unless (memq view '(readable raw))
        (raise-argument-error 'select-view! "(or/c 'readable 'raw)" view))
      (define selection (if (eq? view 'readable) 0 1))
      (set! active-view view)
      (unless (= (send view-tabs get-selection) selection)
        (send view-tabs set-selection selection))
      (send view-tabs
            change-children
            (lambda (_children)
              (list (if (eq? view 'readable)
                        readable-panel
                        raw-panel)))))

    (define/private (delete-rendered-report-cards!)
      (for ([child (in-list (send report-cards-panel get-children))])
        (send report-cards-panel delete-child child))
      (hash-clear! card-controls-by-path))

    (define/private (clear-rendered-report-cards!)
      (send report-cards-panel begin-container-sequence)
      (dynamic-wind
       void
       (lambda ()
         (delete-rendered-report-cards!))
       (lambda ()
         (send report-cards-panel end-container-sequence))))

    (define/private (refresh-field-selection!)
      (for ([(path controls) (in-hash card-controls-by-path)])
        (for ([(field rendered-control)
               (in-hash (card-controls-field-controls controls))])
          (send (field-control-control rendered-control)
                set-label
                (if (and selected-report-field
                         (eq? field selected-report-field))
                    (string-append "> " (field-control-label rendered-control))
                    (field-control-label rendered-control))))))

    (define/private (clear-report-selection!)
      (set! selected-card-path #f)
      (set! selected-report-field #f)
      (refresh-field-selection!))

    (define/private (clear-report-controls!)
      (clear-rendered-report-cards!)
      (hash-clear! card-expanded-by-path)
      (hash-clear! field-limit-by-path)
      (set! rendered-part-limit report-part-batch-size)
      (set! default-card-expanded? #t)
      (clear-report-selection!)
      (send interpretation-message set-label "")
      (send load-more-parts-button show #f))

    (define/public (clear-report!)
      (clear-report-controls!)
      (set! current-report #f))

    (define/private (card-header-label segment expanded?)
      (format "[~a] ~a — ~a"
              (if expanded? "−" "+")
              (report-segment-path segment)
              (report-segment-label segment)))

    (define/private (set-card-expanded! path controls expanded?)
      (hash-set! card-expanded-by-path path expanded?)
      (when expanded?
        (render-card-fields! path controls))
      (send (card-controls-card controls)
            change-children
            (lambda (_children)
              (if expanded?
                  (list (card-controls-header controls)
                        (card-controls-fields-panel controls))
                  (list (card-controls-header controls)))))
      (send (card-controls-header controls)
            set-label
            (card-header-label (card-controls-segment controls) expanded?)))

    (define/private (find-card-controls-for-field field)
      (for/or ([(path controls) (in-hash card-controls-by-path)])
        (and (hash-has-key? (card-controls-field-controls controls) field)
             controls)))

    (define/private (card-path-for-field field)
      (and current-report
           (for/or ([part (in-vector (hl7-report-parts current-report))]
                    #:when (report-segment? part))
             (and (for/or ([candidate (in-vector (report-segment-fields part))])
                    (eq? candidate field))
                  (report-segment-path part)))))

    (define/private (restore-selected-field!)
      (when selected-report-field
        (define controls (find-card-controls-for-field selected-report-field))
        (if controls
            (begin
              (set! selected-card-path
                    (report-segment-path (card-controls-segment controls)))
              (set-card-expanded! selected-card-path controls #t)
              (refresh-field-selection!))
            (set! selected-report-field #f))))

    (define/private (render-card-fields! path controls)
      (define panel (card-controls-fields-panel controls))
      (when (null? (send panel get-children))
        (define segment (card-controls-segment controls))
        (define visible-fields
          (report-segment-visible-fields segment show-empty-fields?))
        (define limit
          (min (vector-length visible-fields)
               (hash-ref field-limit-by-path
                         path
                         report-field-batch-size)))
        (hash-set! field-limit-by-path path limit)
        (for ([field (in-vector visible-fields)]
              [index (in-naturals)]
              #:break (>= index limit))
          (define label
            (bounded-control-label
             (format "~a-~a — ~a: ~a"
                     (report-segment-name segment)
                     (report-field-position field)
                     (report-field-label field)
                     (report-field-raw field))))
          (define button
            (new button%
                 [parent panel]
                 [label label]
                 [callback
                  (lambda (_button _event)
                    (select-report-field! field))]
                 [stretchable-width #t]))
          (hash-set! (card-controls-field-controls controls)
                     field
                     (field-control button label)))
        (when (< limit (vector-length visible-fields))
          (new button%
               [parent panel]
               [label "Load More Fields"]
               [callback
                (lambda (_button _event)
                  (load-more-report-fields! path))]
               [stretchable-width #t]))))

    (define/public (load-more-report-fields! path)
      (unless (string? path)
        (raise-argument-error 'load-more-report-fields! "string?" path))
      (define controls (hash-ref card-controls-by-path path #f))
      (when controls
        (define visible-fields
          (report-segment-visible-fields
           (card-controls-segment controls)
           show-empty-fields?))
        (hash-set! field-limit-by-path
                   path
                   (min (vector-length visible-fields)
                        (+ (hash-ref field-limit-by-path
                                     path
                                     report-field-batch-size)
                           report-field-batch-size)))
        (rebuild-report-cards!)))

    (define/private (render-segment-card! segment)
      (define path (report-segment-path segment))
      (define card
        (new vertical-panel%
             [parent report-cards-panel]
             [style '(border)]
             [alignment '(left top)]
             [spacing 4]
             [border 6]
             [stretchable-width #t]
             [stretchable-height #f]))
      (define controls #f)
      (define header
        (new button%
             [parent card]
             [label (card-header-label segment
                                       (hash-ref card-expanded-by-path
                                                 path
                                                 default-card-expanded?))]
             [callback
              (lambda (_button _event)
                (set! selected-card-path path)
                (unless (and selected-report-field
                             (string=? (card-path-for-field selected-report-field)
                                       path))
                  (set! selected-report-field #f))
                (set-card-expanded!
                 path
                 controls
                 (not (hash-ref card-expanded-by-path
                                path
                                default-card-expanded?)))
                (refresh-field-selection!))]
             [stretchable-width #t]))
      (define fields-panel
        (new vertical-panel%
             [parent card]
             [alignment '(left top)]
             [spacing 2]
             [stretchable-width #t]
             [stretchable-height #f]))
      (define field-controls (make-hasheq))
      (set! controls
            (card-controls card header fields-panel field-controls segment))
      (hash-set! card-controls-by-path path controls)
      (set-card-expanded!
       path
       controls
       (hash-ref card-expanded-by-path path default-card-expanded?)))

    (define/private (render-unparsed-card! part)
      (define card
        (new vertical-panel%
             [parent report-cards-panel]
             [style '(border)]
             [alignment '(left top)]
             [border 6]
             [stretchable-width #t]
             [stretchable-height #f]))
      (define control
        (new button%
             [parent card]
             [label (report-unparsed-label part)]
              [callback
              (lambda (_button _event)
                (select-report-unparsed! part))]
             [stretchable-width #t]))
      (void control))

    (define/private (rebuild-report-cards!)
      (send report-cards-panel begin-container-sequence)
      (dynamic-wind
       void
       (lambda ()
         (delete-rendered-report-cards!)
         (when current-report
           (for ([part (in-vector (hl7-report-parts current-report))]
                 [index (in-naturals)]
                 #:break (>= index rendered-part-limit))
             (cond
               [(report-segment? part) (render-segment-card! part)]
               [(report-unparsed? part) (render-unparsed-card! part)]
               [else
                (raise-arguments-error
                 'rebuild-report-cards!
                 "report contains an unsupported part"
                 "part" part)]))))
       (lambda ()
         (send report-cards-panel end-container-sequence)))
      (when current-report
        (restore-selected-field!)
        (send load-more-parts-button
              show
              (< rendered-part-limit
                 (vector-length (hl7-report-parts current-report))))))

    (define/public (load-more-report-parts!)
      (when current-report
        (set! rendered-part-limit
              (min (vector-length (hl7-report-parts current-report))
                   (+ rendered-part-limit report-part-batch-size)))
        (rebuild-report-cards!)))

    (define/public (populate-report! report)
      (unless (hl7-report? report)
        (raise-argument-error 'populate-report! "hl7-report?" report))
      (clear-report-controls!)
      (set! current-report report)
      (set! default-card-expanded?
            (<= (vector-length (hl7-report-parts report))
                large-report-part-count))
      (send interpretation-message
            set-label
            (report->interpretation-label report))
      (rebuild-report-cards!))

    (define/private (clear-results!)
      (set! current-result #f)
      (clear-report!)
      (set! current-diagnostics #())
      (set! diagnostic-limit diagnostic-batch-size)
      (send diagnostics-list clear)
      (send load-more-diagnostics-button show #f)
      (send source-editor unhighlight-ranges/key 'v2-lens-selection)
      (select-view! 'raw))

    (define/private (source-changed!)
      (cancel-operation!)
      (set! exact-source #f)
      (set! source-position-map #f)
      (clear-results!)
      (set-current-file-label! (and current-display-name #t))
      (send status-message set-label "Source changed — click Parse"))

    (define/private (highlight-span! span)
      (define source-start (hl7-span-start span))
      (define source-end (hl7-span-end span))
      (define start
        (if source-position-map
            (vector-ref source-position-map source-start)
            source-start))
      (define end
        (if source-position-map
            (vector-ref source-position-map source-end)
            source-end))
      (send source-editor unhighlight-ranges/key 'v2-lens-selection)
      (send source-editor
            set-position
            start
            end
            #f
            #t
            'local)
      (send source-editor
            highlight-range
            start
            end
            "gold"
            #t
            'high
            (if (= start end) 'dot 'rectangle)
            #:adjust-on-insert/delete? #t
            #:key 'v2-lens-selection))

    (define/private (show-raw-span! span)
      (clear-report-selection!)
      (select-view! 'raw)
      (highlight-span! span))

    (define/private (rebuild-diagnostics!)
      (send diagnostics-list clear)
      (for ([diagnostic (in-vector current-diagnostics)]
            [index (in-naturals)]
            #:break (>= index diagnostic-limit))
        (send diagnostics-list
              append
              (diagnostic->label diagnostic)
              (hl7-diagnostic-span diagnostic)))
      (send load-more-diagnostics-button
            show
            (< diagnostic-limit (vector-length current-diagnostics))))

    (define/private (populate-diagnostics! result)
      (set! current-diagnostics (hl7-parse-result-diagnostics result))
      (set! diagnostic-limit
            (min diagnostic-batch-size (vector-length current-diagnostics)))
      (rebuild-diagnostics!))

    (define/public (load-more-diagnostics!)
      (set! diagnostic-limit
            (min (vector-length current-diagnostics)
                 (+ diagnostic-limit diagnostic-batch-size)))
      (rebuild-diagnostics!))

    (define/public (set-source-text! text [display-name #f])
      (unless (string? text)
        (raise-argument-error 'set-source-text! "string?" text))
      (unless (or (not display-name) (string? display-name))
        (raise-argument-error 'set-source-text! "(or/c string? #f)" display-name))
      (cancel-operation!)
      (define build-position-map?
        (<= (source-utf-8-size text) max-parse-bytes))
      (define-values (display-text positions)
        (source->display text build-position-map?))
      (set! current-display-name display-name)
      (set! exact-source text)
      (set! source-position-map positions)
      (send source-editor replace-contents display-text)
      (clear-results!)
      (set-current-file-label! #f)
      (send status-message set-label "Source changed — click Parse"))

    (define/private (apply-parse-product! product)
      (define result (vector-ref product 0))
      (define report (vector-ref product 1))
      (set! current-result result)
      (populate-report! report)
      (populate-diagnostics! result)
      (select-view! (if (zero? (vector-length (hl7-report-parts report)))
                        'raw
                        'readable))
      (send status-message set-label (parse-result->status result))
      result)

    (define/private (compute-parse-product source)
      (define result (parser source))
      (vector result (report-builder result)))

    (define/public (parse-source-now!)
      (cancel-operation!)
      (send source-editor unhighlight-ranges/key 'v2-lens-selection)
      (define source (or exact-source (send source-editor get-text)))
      (define refusal (source-parse-refusal source))
      (if refusal
          (begin
            (clear-results!)
            (send status-message set-label refusal)
            #f)
          (apply-parse-product! (compute-parse-product source))))

    (define/public (request-parse!)
      (send source-editor unhighlight-ranges/key 'v2-lens-selection)
      (define source (or exact-source (send source-editor get-text)))
      (define refusal (source-parse-refusal source))
      (cond
        [refusal
         (cancel-operation!)
         (clear-results!)
         (send status-message set-label refusal)
         #f]
        [else
         (clear-results!)
         (start-operation!
          "Parsing…"
          (lambda () (compute-parse-product source))
          (lambda (product) (apply-parse-product! product))
          "Parsing failed — source remains available")]))

    (define/public (parse-source!)
      (request-parse!))

    (define/private (apply-show-empty-fields! value)
      (set! show-empty-fields? value)
      (send show-empty-control set-value value)
      (rebuild-report-cards!))

    (define/private (finish-report-transition!)
      (set! report-transitioning? #f)
      (set! pending-show-empty-value #f)
      (send show-empty-control enable #t)
      (send report-transition-message set-label "")
      (send report-transition-message show #f))

    (define/public (request-show-empty-fields! value)
      (unless (boolean? value)
        (raise-argument-error 'request-show-empty-fields! "boolean?" value))
      (cond
        [report-transitioning?
         (send show-empty-control set-value pending-show-empty-value)]
        [(eq? value show-empty-fields?)
         (send show-empty-control set-value value)]
        [else
         (set! report-transitioning? #t)
         (set! pending-show-empty-value value)
         (send show-empty-control set-value value)
         (send show-empty-control enable #f)
         (send report-transition-message set-label "Updating fields\u2026")
         (send report-transition-message show #t)
         (queue-callback
          (lambda ()
            (complete-pending-report-update!))
          #f)]))

    (define/public (complete-pending-report-update!)
      (when report-transitioning?
        (define value pending-show-empty-value)
        (with-handlers
            ([exn:fail?
              (lambda (problem)
                (finish-report-transition!)
                (raise problem))])
          (apply-show-empty-fields! value)
          (finish-report-transition!))))

    (define/public (set-show-empty-fields! value)
      (unless (boolean? value)
        (raise-argument-error 'set-show-empty-fields! "boolean?" value))
      (when report-transitioning?
        (finish-report-transition!))
      (apply-show-empty-fields! value))

    (define/public (set-all-cards-expanded! expanded?)
      (unless (boolean? expanded?)
        (raise-argument-error 'set-all-cards-expanded! "boolean?" expanded?))
      (for ([(path controls) (in-hash card-controls-by-path)])
        (set-card-expanded! path controls expanded?)))

    (define/public (select-report-field! field)
      (unless (report-field? field)
        (raise-argument-error 'select-report-field! "report-field?" field))
      (define path (card-path-for-field field))
      (unless path
        (raise-arguments-error
         'select-report-field!
         "field is not in the current report"
         "field" field))
      (set! selected-card-path path)
      (set! selected-report-field field)
      (refresh-field-selection!)
      (select-view! 'raw)
      (highlight-span! (report-field-span field)))

    (define/public (select-report-unparsed! part)
      (unless (report-unparsed? part)
        (raise-argument-error
         'select-report-unparsed!
         "report-unparsed?"
         part))
      (unless (and current-report
                   (for/or ([candidate
                             (in-vector (hl7-report-parts current-report))])
                     (eq? candidate part)))
        (raise-arguments-error
         'select-report-unparsed!
         "part is not in the current report"
         "part" part))
      (show-raw-span! (report-unparsed-span part)))

    (define/public (show-report!)
      (select-view! 'readable)
      (cond
        [selected-report-field (restore-selected-field!)]
        [selected-card-path
         (define controls
           (hash-ref card-controls-by-path selected-card-path #f))
         (when controls
           (set-card-expanded! selected-card-path controls #t))])
      (refresh-field-selection!))

    (define/private (open-file!)
      (define path
        (get-file "Open an HL7 v2 message"
                  this
                  #f
                  #f
                  #f
                  '()
                  '(("HL7 messages" "*.hl7;*.txt")
                    ("All files" "*"))))
      (when path
        (request-load-file! path)))

    (define/private (read-utf-8-file path)
      (bytes->string/utf-8 (file->bytes path #:mode 'binary) #f))

    (define/public (load-file-now! path)
      (unless (path-string? path)
        (raise-argument-error 'load-file-now! "path-string?" path))
      (when (file-open-refusal path)
        (raise-arguments-error
         'load-file-now!
         "file exceeds the 100 MiB public beta open limit"
         "path" path))
      (define text (read-utf-8-file path))
      (define filename (file-name-from-path path))
      (set-source-text! text
                        (if filename
                            (path->string filename)
                            (path->string path)))
      (parse-source-now!))

    (define/public (request-load-file! path)
      (unless (path-string? path)
        (raise-argument-error 'request-load-file! "path-string?" path))
      (with-handlers
          ([exn:fail?
            (lambda (_problem)
              (send status-message
                    set-label
                    "Cannot open file — current source remains available")
              #f)])
        (cond
          [(file-open-refusal path)
           (send status-message
                 set-label
                 "Cannot open file — exceeds the 100 MiB public beta limit")
           #f]
          [else
           (define filename (file-name-from-path path))
           (define display-name
             (if filename (path->string filename) (path->string path)))
           (start-operation!
            "Opening…"
            (lambda () (read-utf-8-file path))
            (lambda (text)
              (set-source-text! text display-name)
              (request-parse!))
            "Cannot open file — current source remains available")])))

    (define/public (load-file! path)
      (request-load-file! path))

    (define/public (select-diagnostic! index)
      (unless (exact-nonnegative-integer? index)
        (raise-argument-error 'select-diagnostic! "exact-nonnegative-integer?" index))
      (when (>= index (send diagnostics-list get-number))
        (raise-arguments-error 'select-diagnostic!
                               "diagnostic index is out of range"
                               "index" index))
      (send diagnostics-list set-selection index)
      (show-raw-span! (send diagnostics-list get-data index)))

    (define/public (get-source-editor) source-editor)
    (define/public (get-edit-menu) edit-menu)
    (define/public (get-diagnostics-list) diagnostics-list)
    (define/public (get-current-report) current-report)
    (define/public (get-show-empty-fields?) show-empty-fields?)
    (define/public (get-report-transitioning?) report-transitioning?)
    (define/public (get-report-transition-label)
      (send report-transition-message get-label))
    (define/public (get-view-child-count)
      (length (send view-tabs get-children)))
    (define/public (get-report-cards-stretchable-height?)
      (send report-cards-panel stretchable-height))
    (define/public (get-visible-field-paths path)
      (unless (string? path)
        (raise-argument-error 'get-visible-field-paths "string?" path))
      (define controls (hash-ref card-controls-by-path path #f))
      (if controls
          (for/list
              ([field (in-vector
                       (report-segment-visible-fields
                        (card-controls-segment controls)
                        show-empty-fields?))])
            (report-field-path field))
          '()))
    (define/public (get-card-expanded-states)
      (if current-report
          (for/list ([part (in-vector (hl7-report-parts current-report))]
                     #:when (report-segment? part))
            (hash-ref card-expanded-by-path
                      (report-segment-path part)
                      default-card-expanded?))
          '()))
    (define/public (get-card-child-counts)
      (if current-report
          (for/list ([part (in-vector (hl7-report-parts current-report))]
                     #:when
                     (and (report-segment? part)
                          (hash-has-key? card-controls-by-path
                                         (report-segment-path part))))
            (define controls
              (hash-ref card-controls-by-path (report-segment-path part)))
            (length (send (card-controls-card controls) get-children)))
          '()))
    (define/public (get-card-stretchable-height? path)
      (unless (string? path)
        (raise-argument-error 'get-card-stretchable-height? "string?" path))
      (define controls (hash-ref card-controls-by-path path #f))
      (and controls
           (send (card-controls-card controls) stretchable-height)))
    (define/public (get-fields-panel-stretchable-height? path)
      (unless (string? path)
        (raise-argument-error
         'get-fields-panel-stretchable-height?
         "string?"
         path))
      (define controls (hash-ref card-controls-by-path path #f))
      (and controls
           (send (card-controls-fields-panel controls) stretchable-height)))
    (define/public (get-fields-panel-child-count path)
      (unless (string? path)
        (raise-argument-error 'get-fields-panel-child-count "string?" path))
      (define controls (hash-ref card-controls-by-path path #f))
      (if controls
          (length (send (card-controls-fields-panel controls) get-children))
          0))
    (define/public (get-rendered-field-control-count path)
      (unless (string? path)
        (raise-argument-error
         'get-rendered-field-control-count "string?" path))
      (define controls (hash-ref card-controls-by-path path #f))
      (if controls
          (hash-count (card-controls-field-controls controls))
          0))
    (define/public (get-rendered-field-labels path)
      (unless (string? path)
        (raise-argument-error 'get-rendered-field-labels "string?" path))
      (define controls (hash-ref card-controls-by-path path #f))
      (if controls
          (for/list ([rendered (in-hash-values
                                (card-controls-field-controls controls))])
            (field-control-label rendered))
          '()))
    (define/public (get-card-expanded? path)
      (unless (string? path)
        (raise-argument-error 'get-card-expanded? "string?" path))
      (hash-ref card-expanded-by-path path #f))
    (define/public (get-selected-card-path) selected-card-path)
    (define/public (get-selected-report-field) selected-report-field)
    (define/public (get-report-card-count)
      (length (send report-cards-panel get-children)))
    (define/public (get-unparsed-card-count)
      (if current-report
          (for/sum ([part (in-vector (hl7-report-parts current-report))]
                    #:when (report-unparsed? part))
            1)
          0))
    (define/public (get-active-view) active-view)
    (define/public (get-view-tab-selection)
      (send view-tabs get-selection))
    (define/public (get-interpretation-label)
      (send interpretation-message get-label))
    (define/public (get-status-label) (send status-message get-label))
    (define/public (get-operation-active?) operation-active?)
    (define/public (get-rendered-part-limit) rendered-part-limit)
    (define/public (get-diagnostic-limit) diagnostic-limit)
    (define/public (get-load-more-parts-visible?)
      (send load-more-parts-button is-shown?))
    (define/public (get-load-more-diagnostics-visible?)
      (send load-more-diagnostics-button is-shown?))
    (define/public (get-show-empty-control) show-empty-control)
    (define/public (get-back-to-report-button) back-to-report-button)

    (define/augment (on-close)
      (cancel-operation!)
      (inner (void) on-close))

    (select-view! 'raw)))

(define (run-v2-lens)
  (define frame (new inspector-frame%))
  (send frame show #t)
  (void))

(module+ main
  (run-v2-lens))

(module+ test
  (require rackunit)

  (define (wait-until-idle! target [remaining 500])
    (cond
      [(not (send target get-operation-active?)) (void)]
      [(zero? remaining)
       (error 'wait-until-idle! "operation did not finish")]
      [else
       (sleep/yield 0.01)
       (wait-until-idle! target (sub1 remaining))]))

  (define frame (new inspector-frame%))
  (check-equal? (send frame get-label) "V2 Lens — Public Beta")
  (define edit-menu (send frame get-edit-menu))
  (define paste-item
    (for/or ([item (in-list (send edit-menu get-items))])
      (and (is-a? item selectable-menu-item<%>)
           (string=? (send item get-plain-label) "Paste")
           item)))
  (check-not-false paste-item)
  (check-equal? (send paste-item get-shortcut) #\v)
  (check-equal? (send paste-item get-shortcut-prefix)
                (get-default-shortcut-prefix))
  (check-equal? (send frame get-active-view) 'raw)
  (check-equal? (send frame get-view-tab-selection) 1)
  (check-equal? (send frame get-view-child-count) 1)
  (check-false (send frame get-report-cards-stretchable-height?))

  (send frame set-source-text!
        "MSH|^~\\&|LAB|FAC|||202608181200||ORU^R01|42|P|2.5.1\rOBX|1|NM|HGB||13.8")
  (define parsed (send frame parse-source-now!))
  (check-true (hl7-parse-result-complete? parsed))
  (check-equal? (send frame get-active-view) 'readable)
  (check-equal? (hl7-report-message-version (send frame get-current-report))
                "2.5.1")
  (check-equal? (send frame get-interpretation-label)
                (string-append
                 "Labels use common HL7 v2 terminology. Message version: 2.5.1. "
                 "Schema validation and value interpretation were not performed."))
  (check-equal? (send frame get-status-label)
                "Complete — 2 segments, 0 unparsed parts, 0 diagnostics")
  (send frame select-view! 'raw)
  (check-equal? (send frame get-active-view) 'raw)
  (send frame select-view! 'readable)
  (check-equal? (send frame get-active-view) 'readable)
  (check-equal? (send frame get-view-child-count) 1)

  (send frame set-source-text! "MSH|^~\\&|APP\rBAD!oops\rPID|1")
  (void (send frame parse-source-now!))
  (define diagnostics (send frame get-diagnostics-list))
  (check-equal? (send frame get-active-view) 'readable)
  (check-equal? (vector-length
                 (hl7-report-parts (send frame get-current-report)))
                3)
  (check-equal? (send diagnostics get-number) 1)
  (send frame select-diagnostic! 0)
  (define diagnostic-span (send diagnostics get-data 0))
  (define source-editor (send frame get-source-editor))
  (check-equal? (send source-editor get-start-position)
                (hl7-span-start diagnostic-span))
  (check-equal? (send source-editor get-end-position)
                (hl7-span-end diagnostic-span))
  (check-equal? (length (send source-editor get-highlighted-ranges)) 1)

  (send source-editor insert "X" 0 0)
  (check-false (send frame get-current-report))
  (check-equal? (send frame get-active-view) 'raw)
  (check-equal? (send diagnostics get-number) 0)
  (check-equal? (send source-editor get-highlighted-ranges) '())
  (check-equal? (send frame get-status-label)
                "Source changed — click Parse")

  (define valid-path (make-temporary-file "v2-lens-valid-~a.hl7"))
  (define invalid-path (make-temporary-file "v2-lens-invalid-~a.hl7"))
  (dynamic-wind
   void
   (lambda ()
     (call-with-output-file valid-path
       (lambda (output)
         (write-bytes #"MSH|^~\\&|APP\r\nPID|1" output))
       #:exists 'truncate/replace)
     (call-with-output-file invalid-path
       (lambda (output)
         (write-bytes #"\377" output))
       #:exists 'truncate/replace)
     (define loaded (send frame load-file-now! valid-path))
     (check-true (hl7-parse-result-complete? loaded))
     (check-equal? (hl7-message-source (hl7-parse-result-message loaded))
                   "MSH|^~\\&|APP\r\nPID|1")
     (check-equal? (send source-editor get-text)
                   "MSH|^~\\&|APP\nPID|1")
     (check-equal? (send frame get-active-view) 'readable)
     (check-exn exn:fail?
                (lambda () (send frame load-file-now! invalid-path)))
     (check-equal? (send source-editor get-text)
                   "MSH|^~\\&|APP\nPID|1"))
   (lambda ()
     (delete-file valid-path)
     (delete-file invalid-path)))

  (send frame set-source-text! "MSH|^~\\&|APP\r\nBAD!oops")
  (void (send frame parse-source-now!))
  (send frame select-diagnostic! 0)
  (define crlf-diagnostic-span (send diagnostics get-data 0))
  (check-equal? (send source-editor get-start-position)
                (sub1 (hl7-span-start crlf-diagnostic-span)))
  (check-equal? (send source-editor get-end-position)
                (sub1 (hl7-span-end crlf-diagnostic-span)))
  (check-equal? (length (send source-editor get-highlighted-ranges)) 1)

  (send frame set-source-text!
        "MSH|^~\\&|APP|FAC|||||||P|2.3\rPID|1||ABC||DOE^JANE")
  (void (send frame parse-source-now!))
  (define populated-report (send frame get-current-report))
  (define pid
    (vector-ref (hl7-report-parts populated-report) 1))
  (check-false (send frame get-show-empty-fields?))
  (check-false (send (send frame get-show-empty-control) get-value))
  (check-equal? (send frame get-visible-field-paths "PID[1]")
                '("PID[1]-1" "PID[1]-3" "PID[1]-5"))
  (check-equal? (send frame get-card-expanded-states) '(#t #t))
  (check-equal? (send frame get-card-child-counts) '(2 2))
  (check-false (send frame get-card-stretchable-height? "PID[1]"))
  (check-false (send frame get-fields-panel-stretchable-height? "PID[1]"))
  (define show-empty-checkbox (send frame get-show-empty-control))
  (send show-empty-checkbox set-value #t)
  (send show-empty-checkbox
        command
        (new control-event% [event-type 'check-box]))
  (check-true (send frame get-report-transitioning?))
  (check-false (send show-empty-checkbox is-enabled?))
  (check-equal? (send frame get-report-transition-label) "Updating fields\u2026")
  (check-false (send frame get-show-empty-fields?))
  (send show-empty-checkbox set-value #f)
  (send show-empty-checkbox
        command
        (new control-event% [event-type 'check-box]))
  (check-true (send show-empty-checkbox get-value))
  (define transition-finished (make-semaphore 0))
  (queue-callback
   (lambda ()
     (semaphore-post transition-finished))
   #f)
  (void (yield transition-finished))
  (check-eq? (send frame get-current-report) populated-report)
  (check-false (send frame get-report-transitioning?))
  (check-true (send show-empty-checkbox is-enabled?))
  (check-equal? (send frame get-report-transition-label) "")
  (check-true (send frame get-show-empty-fields?))
  (check-true (send (send frame get-show-empty-control) get-value))
  (check-equal? (send frame get-visible-field-paths "PID[1]")
                '("PID[1]-1" "PID[1]-2" "PID[1]-3" "PID[1]-4" "PID[1]-5"))
  (send frame set-all-cards-expanded! #f)
  (check-true (andmap not (send frame get-card-expanded-states)))
  (check-equal? (send frame get-card-child-counts) '(1 1))
  (send frame set-all-cards-expanded! #t)
  (check-true (andmap values (send frame get-card-expanded-states)))
  (check-equal? (send frame get-card-child-counts) '(2 2))

  (define pid-2 (vector-ref (report-segment-fields pid) 1))
  (define pid-3 (vector-ref (report-segment-fields pid) 2))
  (send frame select-report-field! pid-3)
  (check-equal? (send frame get-active-view) 'raw)
  (check-eq? (send frame get-selected-report-field) pid-3)
  (check-equal? (send frame get-selected-card-path) "PID[1]")
  (check-equal? (send source-editor get-start-position)
                (hl7-span-start (report-field-span pid-3)))
  (check-equal? (send source-editor get-end-position)
                (hl7-span-end (report-field-span pid-3)))
  (send frame show-report!)
  (check-equal? (send frame get-active-view) 'readable)
  (check-true (send frame get-card-expanded? "PID[1]"))
  (check-eq? (send frame get-selected-report-field) pid-3)
  (send frame select-report-field! pid-2)
  (check-equal? (send source-editor get-start-position)
                (hl7-span-start (report-field-span pid-2)))
  (check-equal? (send source-editor get-end-position)
                (hl7-span-end (report-field-span pid-2)))
  (send frame set-show-empty-fields! #f)
  (check-false (send frame get-selected-report-field))
  (check-equal? (send frame get-selected-card-path) "PID[1]")
  (send frame select-report-field! pid-3)
  (check-equal? (length (send source-editor get-highlighted-ranges)) 1)
  (void (send frame parse-source-now!))
  (check-false (send frame get-selected-report-field))
  (check-false (send frame get-selected-card-path))
  (check-equal? (send source-editor get-highlighted-ranges) '())

  (send frame set-source-text!
        "MSH|^~\\&|APP|FAC|||||||P|2.3\r\nPID|1||ABC")
  (void (send frame parse-source-now!))
  (define crlf-pid
    (vector-ref (hl7-report-parts (send frame get-current-report)) 1))
  (define crlf-pid-3 (vector-ref (report-segment-fields crlf-pid) 2))
  (send frame select-report-field! crlf-pid-3)
  (check-equal? (send source-editor get-start-position)
                (sub1 (hl7-span-start (report-field-span crlf-pid-3))))
  (check-equal? (send source-editor get-end-position)
                (sub1 (hl7-span-end (report-field-span crlf-pid-3))))
  (send source-editor insert "X" 0 0)
  (check-false (send frame get-current-report))
  (check-false (send frame get-selected-report-field))
  (check-false (send frame get-selected-card-path))
  (check-equal? (send frame get-report-card-count) 0)

  (send frame set-source-text! "MSH|^~\\&|APP\rBAD!oops\rPID|1")
  (void (send frame parse-source-now!))
  (define partial-report (send frame get-current-report))
  (define unparsed-part (vector-ref (hl7-report-parts partial-report) 1))
  (check-equal? (send frame get-active-view) 'readable)
  (check-equal? (send frame get-report-card-count) 3)
  (check-equal? (send frame get-unparsed-card-count) 1)
  (check-true (report-unparsed? unparsed-part))
  (send frame select-report-unparsed! unparsed-part)
  (check-equal? (send frame get-active-view) 'raw)
  (check-equal? (send source-editor get-start-position)
                (hl7-span-start (report-unparsed-span unparsed-part)))
  (check-equal? (send source-editor get-end-position)
                (hl7-span-end (report-unparsed-span unparsed-part)))
  (send frame show-report!)
  (check-equal? (send frame get-active-view) 'readable)
  (send frame select-diagnostic! 0)
  (check-equal? (send frame get-active-view) 'raw)

  (send frame set-source-text! "PID|1")
  (void (send frame parse-source-now!))
  (check-equal? (vector-length
                 (hl7-report-parts (send frame get-current-report)))
                0)
  (check-equal? (send frame get-report-card-count) 0)
  (check-equal? (send frame get-card-expanded-states) '())
  (check-false (send frame get-selected-report-field))
  (check-equal? (send frame get-active-view) 'raw)
  (check-equal? (send diagnostics get-number) 1)
  (check-equal? (send frame get-status-label)
                "Incomplete — 0 segments, 0 unparsed parts, 1 diagnostics")

  (define long-field-source
    (string-append
     "MSH|^~\\&|APP\rZZZ|"
     (make-string 300 #\X)
     (apply string-append
            (for/list ([index (in-range 100)])
              (format "|~a" index)))))
  (send frame set-source-text! long-field-source)
  (void (send frame parse-source-now!))
  (check-equal? (send frame get-rendered-field-control-count "ZZZ[1]")
                report-field-batch-size)
  (check-equal? (send frame get-fields-panel-child-count "ZZZ[1]")
                (add1 report-field-batch-size))
  (check-true
   (for/and ([label (in-list
                     (send frame get-rendered-field-labels "ZZZ[1]"))])
     (<= (string-length label) max-field-control-label-length)))
  (check-true
   (for/or ([label (in-list
                    (send frame get-rendered-field-labels "ZZZ[1]"))])
     (= (string-length label) max-field-control-label-length)))
  (send frame load-more-report-fields! "ZZZ[1]")
  (check-equal? (send frame get-rendered-field-control-count "ZZZ[1]") 101)

  (define large-report-source
    (string-append
     "MSH|^~\\&|APP"
     (apply string-append
            (for/list ([index (in-range 100)])
              (format "\rPID|~a" index)))))
  (send frame set-source-text! large-report-source)
  (void (send frame parse-source-now!))
  (check-equal? (send frame get-report-card-count) report-part-batch-size)
  (check-true (send frame get-load-more-parts-visible?))
  (check-true (andmap not (send frame get-card-expanded-states)))
  (send frame load-more-report-parts!)
  (check-equal? (send frame get-report-card-count) 101)
  (check-false (send frame get-load-more-parts-visible?))

  (define many-diagnostics-source
    (string-append
     "MSH|^~\\&|APP"
     (apply string-append
            (for/list ([index (in-range 251)])
              "\rBAD!oops"))))
  (send frame set-source-text! many-diagnostics-source)
  (void (send frame parse-source-now!))
  (check-equal? (send diagnostics get-number) diagnostic-batch-size)
  (check-true (send frame get-load-more-diagnostics-visible?))
  (send frame load-more-diagnostics!)
  (check-equal? (send diagnostics get-number) 251)
  (check-false (send frame get-load-more-diagnostics-visible?))

  (send frame set-source-text! "MSH|^~\\&|APP\rPID|1")
  (void (send frame request-parse!))
  (wait-until-idle! frame)
  (check-true (hl7-report? (send frame get-current-report)))

  (define worker-started (make-semaphore 0))
  (define worker-release (make-semaphore 0))
  (define cancellation-frame
    (new inspector-frame%
         [parser
          (lambda (source)
            (semaphore-post worker-started)
            (semaphore-wait worker-release)
            (parse-hl7-v2 source))]))
  (send cancellation-frame set-source-text! "MSH|^~\\&|APP")
  (void (send cancellation-frame request-parse!))
  (semaphore-wait worker-started)
  (check-true (send cancellation-frame get-operation-active?))
  (send (send cancellation-frame get-source-editor) insert "X" 0 0)
  (check-false (send cancellation-frame get-operation-active?))
  (semaphore-post worker-release)
  (sleep/yield 0.02)
  (check-false (send cancellation-frame get-current-report))

  (define failure-frame
    (new inspector-frame%
         [parser (lambda (_source) (error 'test-parser "source details"))]))
  (send failure-frame set-source-text! "MSH|^~\\&|APP")
  (void (send failure-frame request-parse!))
  (wait-until-idle! failure-frame)
  (check-false (send failure-frame get-current-report))
  (check-equal? (send failure-frame get-status-label)
                "Parsing failed — source remains available")
  (check-false (regexp-match? #rx"source details"
                              (send failure-frame get-status-label)))
  (send cancellation-frame show #f)
  (send failure-frame show #f)
  (send frame show #f))
