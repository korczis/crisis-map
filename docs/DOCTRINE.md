# Doctrine

The rules this repository is built on, and the test that makes each one true
rather than aspirational. A rule without an enforcing test is a preference;
the gate `test "every rule names a test that enforces it"` in
`test/crisis_map/doctrine_test.exs` fails when a rule listed here names a test
that does not exist.

## D1 — One definition, many projections

An operation is declared once, in a capability provider. Routes, the OpenAPI
document, MCP tools, CLI switches, cockpit forms, reference documentation and
the benchmark inventory are generated from that declaration. Editing a
transport, a specification or a table to add an operation is a defect, not a
change.

Enforced by: `test "an HTTP route exists with the declared method and path"`,
`test "the OpenAPI document describes it"`,
`test "the MCP tool list exposes it with a schema"`,
`test "the command line accepts it"`.

## D2 — Documented, or it does not ship

Every capability carries a summary, a description that explains the operation,
a statement of what it returns, and a description for every parameter.

Enforced by: `test "with a summary, a description and a statement of what it returns"`,
`test "with every parameter described"`.

## D3 — Every capability has a runnable example

Examples are not decoration: they are what the documentation prints, what the
OpenAPI document carries, and what the benchmark inventory measures. An
example that no longer satisfies its own schema is a failing build.

Enforced by: `test "with at least one runnable example"`.

## D4 — Tested

Every capability is named by a test. A capability nobody exercised cannot
appear on four surfaces at once.

Enforced by: `test "a test names it"`.

## D5 — Benchmarked

Every capability is measured, through its own examples, at the same entry
point every surface uses.

Enforced by: `test "the benchmark inventory measures it"`.

## D6 — Generated documentation is kept in sync

What is committed under `docs/` must equal what the registry would produce
now. There is no second, hand-written description of the API.

Enforced by: `test "every generated file matches what the registry would produce now"`,
`test "no hand-written API specification is kept alongside the inferred one"`.

## D7 — The vocabulary is declared once

Event types, geocoding statuses and reference points live in
`CrisisMap.Catalog`. Validation, the filter, the map colours, the API and the
documentation read them from there; none keeps a copy.

Enforced by: `test "event types are unique, labelled, described and coloured"`,
`test "the fallback type is itself a declared type"`,
`test "every geocoding status says whether coordinates are known"`,
`test "exactly one status means the coordinates are known"`.

## D8 — Every module is documented

Enforced by: `test "every module of the application carries a moduledoc"`.

## D9 — Nothing invents a position

A position is stored only when a geocoder returned one. Every other outcome is
a status that says why there is none, and the schema refuses a row that claims
otherwise.

Enforced by: `test "an unknown location keeps the event, keeps the text and invents no coordinates"`,
`test "a status that claims coordinates cannot be stored without a point"`,
`test "a status that denies coordinates cannot be stored with a point"`.

## D10 — One bad record never ends a run

Enforced by: `test "a geocoder that is down costs the record its position, not the import"`,
`test "one failing record does not stop the ones after it"`,
`test "an unusable record is reported and the rest of the file still imports"`.
