# V2 Lens API reference

V2 Lens version 0.1 exports one parser, eleven transparent structure types,
and navigation helpers from the `v2-lens` collection.

```racket
(require v2-lens)
```

## Parser

### `parse-hl7-v2`

```text
(parse-hl7-v2 text) → hl7-parse-result?
  text : string?
```

Parses `text` as one HL7 v2 message. Passing a non-string raises a contract
error. The parser copies the source into an immutable string before producing
the result.

The result has these states:

| `message` | `complete?` | Meaning |
| --- | --- | --- |
| `hl7-message` | `#t` | Every segment was structurally parsed and there are no diagnostics. |
| `hl7-message` | `#f` | A message tree exists, but one or more recoverable problems produced diagnostics. |
| `#f` | `#f` | The input was empty, or a fatal header or separator problem prevented construction of a message tree. |

## Structures

All structures are transparent and immutable. Each `struct-out` export
provides its constructor, predicate, and field accessors. Parser-produced
strings and vectors are immutable.

For every row below, the constructor has the structure's name, its predicate
adds `?`, and each accessor joins the structure and field names. For example,
`hl7-span` provides `hl7-span`, `hl7-span?`, `hl7-span-start`, and
`hl7-span-end`. No structure mutators are exported.

| Structure | Fields | Description |
| --- | --- | --- |
| `hl7-span` | `start`, `end` | Zero-based, half-open Racket character offsets. |
| `hl7-separators` | `field`, `component`, `repetition`, `escape`, `subcomponent` | Separator characters declared by `MSH-1` and `MSH-2`. A fifth truncation character in `MSH-2` is retained in the field's raw value but is not a field of this structure. |
| `hl7-parse-result` | `message`, `diagnostics`, `complete?` | The optional message tree, immutable diagnostic vector, and completion flag. |
| `hl7-diagnostic` | `code`, `message`, `span` | A symbolic code, human-readable message, and source span. |
| `hl7-message` | `source`, `separators`, `terminator`, `parts`, `span` | The complete source, declared separators, first observed segment terminator or `#f`, ordered parsed and unparsed parts, and whole-message span. |
| `hl7-segment` | `name`, `raw`, `fields`, `span` | A parsed segment and its immutable vector of fields. |
| `hl7-unparsed-segment` | `raw`, `span` | A source segment retained after a recoverable structural failure. |
| `hl7-field` | `raw`, `repetitions`, `span` | A field split into repetitions. |
| `hl7-repetition` | `raw`, `components`, `span` | A repetition split into components. |
| `hl7-component` | `raw`, `subcomponents`, `span` | A component split into subcomponents. |
| `hl7-subcomponent` | `raw`, `span` | A leaf value. |

Empty fields and empty lower-level values remain represented in the tree.
Escape-delimited text is kept encoded and is not split on separator characters
inside the escape sequence.

## Navigation helpers

### `hl7-message-segments`

```text
(hl7-message-segments message) → (vectorof hl7-segment?)
```

Returns an immutable vector containing only parsed segments, in source order.

### `hl7-message-unparsed-parts`

```text
(hl7-message-unparsed-parts message) → (vectorof hl7-unparsed-segment?)
```

Returns an immutable vector containing only unparsed segments, in source
order. Use `hl7-message-parts` to retain the interleaving of both kinds.

### `hl7-message-segment`

```text
(hl7-message-segment message name [occurrence 1]) → (or/c hl7-segment? #f)
```

Returns the 1-based occurrence of `name`, or `#f` when it is absent. `name`
must contain exactly three uppercase ASCII letters or digits. `occurrence` must
be an exact positive integer.

### Indexed child accessors

```text
(hl7-segment-field segment index) → (or/c hl7-field? #f)
(hl7-field-repetition field index) → (or/c hl7-repetition? #f)
(hl7-repetition-component repetition index) → (or/c hl7-component? #f)
(hl7-component-subcomponent component index) → (or/c hl7-subcomponent? #f)
```

Each helper uses a 1-based exact positive integer. An index beyond the vector
returns `#f`; zero, a negative value, or another value type raises a contract
error.

### Generic node accessors

```text
(hl7-node-raw node) → string?
(hl7-node-span node) → hl7-span?
```

These functions accept `hl7-message`, `hl7-segment`,
`hl7-unparsed-segment`, `hl7-field`, `hl7-repetition`, `hl7-component`, or
`hl7-subcomponent`. Other values raise a contract error.

For every parser-produced node, slicing `hl7-message-source` from
`hl7-span-start` to `hl7-span-end` yields that node's raw value.

## Structural conventions

- Segment terminators may be CR, LF, or CRLF. `hl7-message-terminator` reports
  the first observed form. Later differences produce a diagnostic.
- Segment, field, repetition, component, and subcomponent lookup uses HL7's
  1-based positions.
- Spans use zero-based, half-open Racket character offsets, not byte offsets.
- Unicode content is retained; one Racket character advances a span by one.
- `MSH-1` and `MSH-2` are exposed as the first two fields of the `MSH`
  segment.
- Segment names must be three uppercase ASCII letters or digits. Unknown and
  site-specific names are structurally accepted when they satisfy this rule.

## Diagnostics

| Code | Effect | Condition |
| --- | --- | --- |
| `empty-input` | Fatal | The source is empty. |
| `missing-msh` | Fatal | The first segment is not `MSH`. |
| `invalid-msh` | Fatal | The first segment cannot supply a valid structural message header. |
| `invalid-separators` | Fatal | Required separator characters are not distinct printable ASCII punctuation. |
| `invalid-segment-name` | Recoverable | A later segment name is malformed or is not followed by the field separator. |
| `unterminated-escape` | Recoverable | An escape character has no closing escape character in its segment. |
| `mixed-segment-terminators` | Recoverable | A later terminator differs from the first observed terminator. |
| `empty-segment` | Recoverable | Two terminators enclose an empty segment. |

A recoverable problem retains the failed source segment as an
`hl7-unparsed-segment` and parsing continues with later segments. An
unterminated escape in `MSH` is also recoverable once its separator declaration
has been established; the `MSH` source is retained as an unparsed segment.

## Related documentation

- [Inspect your first message](tutorial-first-inspection.md)
- [How to parse a message in Racket](how-to-parse-a-message.md)
- [Understanding the structural model](explanation-structural-model.md)
