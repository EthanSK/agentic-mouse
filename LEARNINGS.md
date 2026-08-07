# Learnings

---

**Date:** 2026-08-07
**Trigger:** Ethan explicitly chose Agentic Mouse as the source-and-build home for shared Corsair Scimitar and left-handed Razer Naga Karabiner actions while deferring physical bindings.
**Observed:** Karabiner complex modifications are installed as complete JSON rule documents; one live rule cannot import or reference several independently maintained source files. The safe separation is therefore source-level: one JSONC file per named semantic action, a separate device-binding file, and a deterministic generator that emits the single installable artifact.
**Required response:** Keep action behavior and physical device transports in separate inputs. Require an exact `device_if` on every binding, fail closed on unknown actions or private device-address matching, generate zero rules when the binding layer is empty, and treat generated JSON as read-only build output.
**Evidence:** `Scripts/generate-karabiner.py`, `Tests/KarabinerGeneratorTests/test_generate_karabiner.py`, and `Karabiner/generated/agentic-mouse.json`.
**Where encoded:** `AGENTS.md`, `Karabiner/README.md`, and the generator/tests above.

---
