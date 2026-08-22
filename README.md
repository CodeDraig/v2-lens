# V2 Lens

![V2 Lens magnifying lens inspecting structured message fields](assets/v2-lens-banner.png)

V2 Lens is a Racket library and desktop inspector for the structure of HL7 v2
messages. It builds an immutable tree while retaining every raw value and its
exact character span in the source message.

V2 Lens handles structure only. It does not decode escapes, validate against
an HL7 schema, interpret clinical values, identify PHI, rewrite messages, or
save edits. The desktop application does not log message contents, use the
network, or persist source text automatically.

## Start here

- [Inspect your first message](docs/tutorial-first-inspection.md) is a guided
  lesson for new desktop-inspector users.
- [How to parse a message in Racket](docs/how-to-parse-a-message.md) shows how
  to handle complete and incomplete results in working code.
- [V2 Lens API reference](docs/reference.md) lists the parser's public data
  structures, functions, conventions, and diagnostics.
- [Understanding the structural model](docs/explanation-structural-model.md)
  explains why V2 Lens preserves raw text and spans without interpreting the
  message.

## Install from this checkout

```sh
raco pkg install --auto --name v2-lens
```

## Launch the inspector

```sh
v2-lens
```

If Racket's user launcher directory is not on `PATH`, launch the installed
application through Racket instead:

```sh
racket -e '(require v2-lens/gui) (run-v2-lens)'
```

Paste an HL7 v2 message and choose **Parse**, or choose **Open…** to load and
immediately parse a UTF-8 `.hl7` or text file.

## Parse from Racket

```racket
#lang racket/base

(require v2-lens)

(define result
  (parse-hl7-v2 "MSH|^~\\&|APP|FAC\rPID|1|DEMO-001"))

(displayln (hl7-parse-result-complete? result))
```

See [How to parse a message in Racket](docs/how-to-parse-a-message.md) for
result handling and tree navigation.

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
