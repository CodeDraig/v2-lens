# V2 Lens

![V2 Lens magnifying lens inspecting structured message fields](assets/v2-lens-banner.png)

V2 Lens parses HL7 v2 messages into an immutable structural tree. It keeps
raw values and character spans so its desktop inspector can connect every
structural node and diagnostic back to the exact source text.

The parser and inspector handle structure only. They do not decode escapes,
render or rewrite messages, apply schemas, or identify PHI. The Rust source
under `reference/rust/` is retained as an inspectable example only; its
behavior is not a compatibility contract.

## Install from this checkout

```sh
raco pkg install --auto --name v2-lens
```

## Inspect a message

Launch the installed desktop application:

```sh
v2-lens
```

Paste an HL7 v2 message into the source pane and choose **Parse**, or choose
**Open…** to load and immediately parse a UTF-8 `.hl7` or text file. Expand
the **Readable** report to inspect segments and fields. Segment cards use
common HL7 v2 terminology for `MSH`, `PID`, `PV1`, `ORC`, `OBR`, `OBX`, `NTE`,
and `SPM`, while preserving every field's exact encoded value. Unknown and
site-specific segments remain visible with generic numbered fields.

Only populated fields appear initially. Use **Show empty fields**, **Expand
All**, and **Collapse All** to change the report display. Selecting a field
opens **Raw Source** and highlights the exact characters parsed for that field;
use **Back to Report** to return to the same selected row. Diagnostics remain
visible in both views.

Display labels are common terminology, not schema validation or clinical
interpretation. The interpretation notice reports the version found in
`MSH-12` when present and identifies use of common terminology or common-label
fallback. Missing, unsupported, and site-specific definitions fall back to
generic labels without hiding parsed content.

The parser retains the file's original CR, LF, or CRLF terminators while the
source pane displays each terminator as a normal line break. Selecting a
diagnostic highlights its exact source span.

Manual source edits immediately clear the old report, selections, and
diagnostics so stale spans cannot be selected; choose **Parse** again to
inspect the changed text.
The inspector does not save files, log message contents, use the network, or
persist source text automatically.

## Parse a message

```racket
#lang racket/base

(require racket/match
         v2-lens)

(define result
  (parse-hl7-v2 "MSH|^~\\&|APP|FAC\rPID|1|λ雪"))

(match result
  [(hl7-parse-result message diagnostics complete?)
   (if complete?
       (displayln (hl7-node-raw (hl7-message-segment message "PID")))
       (for ([diagnostic (in-vector diagnostics)])
         (displayln (hl7-diagnostic-message diagnostic))))])
```

The result contains parsed segments, any recoverable unparsed segments, and
diagnostics. Segment, field, repetition, component, and subcomponent accessors
use the HL7 convention of 1-based indices. Spans use zero-based Racket
character offsets and are half-open.

## Future scope

PHI identification and removal remain a separate future layer. Message
rewriting, decoded values, schema-aware labels, and saving edited messages are
also intentionally absent from this first inspector.

## Acknowledgments

V2 Lens was informed by Kenton Hamaluik's
[hl7-parser](https://github.com/hamaluik/hl7-parser) Rust project, which was
studied as an idea and reference source. V2 Lens is an independent Racket
implementation and does not claim API or behavioral compatibility with that
project. The retained reference snapshot remains under `reference/rust/`.
