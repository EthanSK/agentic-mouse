# Karabiner semantic actions

This folder is Agentic Mouse's source-and-build home for the shared action
vocabulary used by the Corsair Scimitar and left-handed Razer Naga. It contains
no live profile and currently binds no physical button.

## Structure

```text
Karabiner/
  actions/                 One commented JSONC file per semantic action
    app-switching/
    media/
    navigation/
    productivity/
    vscode/
  bindings/bindings.json   Deliberately empty physical adapter layer
  generated/
    action-catalog.json    Combined, browsable action vocabulary
    agentic-mouse.json     Importable Karabiner complex modifications
```

The generator recursively discovers action files, so future modes and submenus
can live in new named subfolders without turning one source file into a large
catch-all. Every action filename equals its stable action ID, and the first line
describes its behavior.

## Build and validate

```bash
make karabiner
make test-karabiner
```

`Scripts/generate-karabiner.py` combines the separate actions because
Karabiner cannot reference action fragments across files. The checked-in
`generated/agentic-mouse.json` is valid Karabiner complex-modification JSON.
Its `rules` array is intentionally empty today: an empty valid artifact is
safer than a placeholder key that could accidentally become live.

`action-catalog.json` proves which action definitions were discovered and is
useful for review or future UI work. It is not installed into Karabiner.

## Adding physical positions later

After Ethan chooses the final physical layout, add entries to
`bindings/bindings.json`. Each entry supplies:

- a stable binding ID and human description;
- one action ID from `actions/`;
- the exact observed `from` event;
- an exact `device_if` condition;
- an optional rule name for grouping.

Example shape only—not an approved or live binding:

```json
{
  "id": "example-razer-cell",
  "description": "Example only",
  "action": "go-back",
  "rule": "Razer base layer",
  "from": { "key_code": "1" },
  "conditions": [
    {
      "type": "device_if",
      "identifiers": [
        { "vendor_id": 0, "product_id": 0, "is_keyboard": true }
      ]
    }
  ]
}
```

Never copy that placeholder identifier. Capture the real event first and keep
private serials out of Git. Match corresponding physical cells rather than the
printed numbers: the two mice number several rows in opposite directions.

## Ownership and verification

- iCUE owns Corsair DPI, profiles, lighting and neutral source transports.
- The Naga onboard profile owns its hardware transports.
- Karabiner owns enabled, exact-device live mappings.
- Agentic Mouse owns these semantic sources, the generator, and its separately
  approved runtime modes.

Static generation and Karabiner lint do not prove a mouse. A later binding is
accepted only after its source event, device attribution, normal behavior,
app-specific behavior, and both-mice coexistence are physically tested.
