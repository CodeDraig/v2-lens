# Understanding the structural model

V2 Lens treats an HL7 v2 message as encoded source with a nested structure. It
answers two questions: “What structural node is this?” and “Which exact source
characters produced it?” It deliberately does not answer what a clinical value
means.

## A lossless structural tree

HL7 v2 separators define a hierarchy:

```text
message
└── segment
    └── field
        └── repetition
            └── component
                └── subcomponent
```

V2 Lens represents every level, including empty values. Each node retains its
encoded raw text and a zero-based, half-open character span. Slicing the
original source with that span recreates the node's raw value.

This pairing matters because the same text can occur in several fields. The
desktop inspector does not search for a selected value; it follows the field's
span to the one location that produced that node. CR, LF, and CRLF terminators
can therefore be displayed uniformly without losing their original positions.

## Immutability preserves the evidence

The parser copies its input and builds immutable strings, vectors, and
structures. A caller cannot change the source after parsing and silently make
the stored spans refer to different characters. A new source requires a new
parse result.

The inspector applies the same rule at the interface boundary. Editing its
source pane immediately clears the old report, diagnostics, selection, and
highlights. Parsing again establishes a new relationship between source and
structure.

## Structural parsing is not interpretation

An encoded field such as `Isaac\S\2` stays encoded. V2 Lens recognizes the
escape delimiters so that the `\S\` contents do not split the field, but it
does not replace the escape with a separator. Likewise, it identifies fields
by position without deciding whether their values are clinically correct.

The readable inspector can attach common names such as “Observation Value” to
known positions. Those labels are navigation aids, not proof that the message
conforms to a particular HL7 schema. Unknown and site-specific segments remain
visible with generic numbered fields.

Keeping these responsibilities separate prevents a display label, decoded
value, or schema assumption from being mistaken for source evidence. It also
leaves interpretation layers free to make their own version, profile, and
local-site choices on top of the same structural result.

## Recovery preserves partial knowledge

Not every structural problem invalidates the whole message. If the initial
`MSH` declaration cannot establish separators, V2 Lens cannot parse the rest
of the source and returns diagnostics without a message tree.

After separators are known, a malformed segment can be retained as an
unparsed part while later valid segments are still structured. The result is
marked incomplete and carries diagnostics, but its ordered parts preserve both
what was understood and what was not. This lets a caller choose whether
partial structure is useful instead of forcing every problem into total
failure.

## Parser and inspector responsibilities

The public parser owns structural facts: separators, hierarchy, raw values,
spans, ordered parts, and diagnostics. The desktop inspector presents those
facts, adds common terminology for readability, and connects report rows and
diagnostics back to source spans.

Neither layer currently decodes escape values, rewrites messages, validates
schemas, interprets clinical content, identifies or removes PHI, saves edited
messages, or persists source text. The retained Rust implementation under
`reference/rust/` is an inspectable source of ideas, not a compatibility
contract.

## Related documentation

- Learn the desktop workflow in
  [Inspect your first message](tutorial-first-inspection.md).
- Apply the parser in a program with
  [How to parse a message in Racket](how-to-parse-a-message.md).
- Look up exact structures and behavior in the
  [V2 Lens API reference](reference.md).
