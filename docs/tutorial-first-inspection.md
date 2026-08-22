# Inspect your first message

This lesson walks through one complete inspection in the V2 Lens desktop
application. You will parse a small synthetic HL7 v2 message, find an
observation value, and connect that field to the exact characters in the
source.

The sample is invented for this tutorial and contains no real patient data.

## Before you begin

Install [Racket](https://racket-lang.org/) and open a terminal in the V2 Lens
checkout. Install the package:

```sh
raco pkg install --auto --name v2-lens
```

## 1. Launch V2 Lens

Run:

```sh
v2-lens
```

If the shell reports `v2-lens: command not found`, Racket's user launcher
directory is not on `PATH`. Launch the installed application through Racket:

```sh
racket -e '(require v2-lens/gui) (run-v2-lens)'
```

The V2 Lens window opens in the **Raw Source** view. Its status reads
`Paste or open an HL7 v2 message`.

## 2. Paste the sample message

Paste this message into the source pane:

```text
MSH|^~\&|TRAINING|LAB|||202608221200||ORU^R01|DEMO-1|P|2.5.1
PID|1||DEMO-001||Example^Patient
OBX|1|NM|HGB^Hemoglobin||13.8|g/dL
```

The window reports `Source changed — click Parse`. This also confirms that an
edit cleared any result that had been associated with the previous source.

## 3. Parse the message

Choose **Parse**.

V2 Lens switches to **Readable** and reports:

```text
Complete — 3 segments, 0 unparsed parts, 0 diagnostics
```

The interpretation notice identifies message version `2.5.1` and states that
schema validation and value interpretation were not performed.

## 4. Find the observation value

Choose **Expand Loaded**. Find the **Observation Result** (`OBX`) card, then find
field `OBX-5`, labeled **Observation Value**. Its encoded value is `13.8`.

Only populated fields appear initially. **Show empty fields** reveals the
empty positions that are still present in the parsed structure.

## 5. Connect the field to its source

Select the `OBX-5` row.

V2 Lens opens **Raw Source** and highlights the exact `13.8` characters. The
highlight is a source span from the structural parser; it is not a search for
matching text.

Choose **Back to Report**. V2 Lens returns to the same selected field in the
readable report.

## What you learned

You completed the basic inspection cycle: provide source text, parse it, find
a structural field, and trace that field back to its exact source characters.

Next:

- Use [How to parse a message in Racket](how-to-parse-a-message.md) when you
  need the same structural data in a program.
- Consult the [API reference](reference.md) for exact types and lookup rules.
- Read [Understanding the structural model](explanation-structural-model.md)
  to learn why the inspector preserves encoded text instead of interpreting
  it.
