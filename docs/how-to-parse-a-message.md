# How to parse a message in Racket

Use this guide when a Racket program must parse an HL7 v2 message, navigate the
available structure, and handle both complete and incomplete results. It
assumes you are comfortable writing and running Racket modules.

Install V2 Lens from its checkout before running the example:

```sh
raco pkg install --auto --name v2-lens
```

## Parse and inspect the result

Save this program as `inspect-message.rkt`:

```racket
#lang racket/base

(require v2-lens)

(define source
  "MSH|^~\\&|LAB|FAC|||202608221200||ORU^R01|42|P|2.5.1\rOBX|1|NM|HGB^Hemoglobin||13.8|g/dL")

(define result (parse-hl7-v2 source))
(define message (hl7-parse-result-message result))

(printf "complete: ~a\n" (hl7-parse-result-complete? result))

(for ([diagnostic (in-vector (hl7-parse-result-diagnostics result))])
  (define span (hl7-diagnostic-span diagnostic))
  (printf "~a at ~a:~a — ~a\n"
          (hl7-diagnostic-code diagnostic)
          (hl7-span-start span)
          (hl7-span-end span)
          (hl7-diagnostic-message diagnostic)))

(cond
  [(not message)
   (displayln "The message header could not be parsed.")]
  [else
   (define obx (hl7-message-segment message "OBX"))
   (cond
     [(not obx)
      (displayln "No OBX segment is available.")]
     [else
      (define observation (hl7-segment-field obx 5))
      (cond
        [(not observation)
         (displayln "The OBX segment has no fifth field.")]
        [else
         (define span (hl7-node-span observation))
         (define source-value
           (substring source
                      (hl7-span-start span)
                      (hl7-span-end span)))
         (unless (string=? source-value (hl7-node-raw observation))
           (error 'inspect-message "field span does not match its raw value"))
         (printf "OBX-5: ~a\n" (hl7-node-raw observation))])])])
```

Run it:

```sh
racket inspect-message.rkt
```

The complete sample prints:

```text
complete: #t
OBX-5: 13.8
```

## Handle incomplete results

Always inspect the three parts of `hl7-parse-result` separately:

- `message` is `#f` when V2 Lens cannot establish a usable message header.
  Diagnostics still describe the failure.
- `message` can be present while `complete?` is `#f`. In this case, valid
  segments remain navigable, failed segments appear as
  `hl7-unparsed-segment` values, and diagnostics identify the problems.
- `complete?` is `#t` only when the diagnostic vector is empty.

Do not discard a present message merely because it is incomplete. Decide
whether the parsed segments are useful for your task, and separately decide
how to report or reject each diagnostic.

Use `hl7-message-unparsed-parts` to enumerate source segments that could not be
structured. Use `hl7-message-parts` when you must preserve the original order
of parsed and unparsed segments.

## Navigate repeated structures

`hl7-message-segment` accepts an optional 1-based occurrence number for
repeated segment names. Field, repetition, component, and subcomponent helpers
also use 1-based indices. A well-formed but absent occurrence or position
returns `#f`; zero and negative indices raise a contract error.

Consult the [API reference](reference.md) for the complete data model and
diagnostic catalog. For a guided visual first experience, use
[Inspect your first message](tutorial-first-inspection.md). To understand the
raw-value and span design, read
[Understanding the structural model](explanation-structural-model.md).
