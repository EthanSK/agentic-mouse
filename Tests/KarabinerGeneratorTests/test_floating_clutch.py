import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

class FloatingClutchRulesTests(unittest.TestCase):
    def test_exact_corsair_clutch_precedes_modes_and_has_unconditional_release(self):
        document = json.loads((ROOT / "Karabiner/generated/agentic-mouse-runtime.json").read_text())
        self.assertIn("Locked-session", document["rules"][0]["description"])
        rule = document["rules"][1]
        self.assertEqual(rule["description"], "Agentic Mouse — Floating Mouse clutch")
        self.assertEqual(len(rule["manipulators"]), 1)
        item = rule["manipulators"][0]
        self.assertEqual(item["from"]["key_code"], "keypad_1")
        self.assertTrue(any(c["type"] == "device_if" for c in item["conditions"]))
        self.assertTrue(any("agentic_mouse_floating_corsair1_expires_at" in c.get("expression", "") for c in item["conditions"]))
        for field, phase in [("to", "press"), ("to_after_key_up", "release")]:
            event = item[field][0]
            self.assertFalse(event["repeat"])
            self.assertEqual(event["send_user_command"]["payload"], {"command": "agentic_mouse_floating_clutch", "source": "corsair1", "phase": phase})
            self.assertFalse(any("floating_corsair1" in c.get("expression", "") for c in event.get("conditions", [])))
        self.assertNotIn("to_if_alone", item)
        # The ordinary horizontal-wheel route remains available after expiry.
        self.assertTrue(any("horizontal" in str(r).lower() for r in document["rules"][2:]))

    def test_passive_edges_preserve_normal_actions_and_all_security_gates(self):
        document = json.loads((ROOT / "Karabiner/generated/agentic-mouse-runtime.json").read_text())
        observed = []
        for rule in document["rules"]:
            for item in rule["manipulators"]:
                edges = [(field, event) for field in ("to", "to_after_key_up")
                         for event in item.get(field, [])
                         if event.get("send_user_command", {}).get("payload", {}).get("command") == "agentic_mouse_floating_clutch"]
                if not edges:
                    continue
                self.assertEqual(item["from"]["key_code"], "keypad_1")
                self.assertTrue(any(c.get("type") == "device_if" and
                                    any(d.get("vendor_id") == 6940 for d in c["identifiers"])
                                    for c in item["conditions"]))
                self.assertEqual(len(edges), 2)
                for field, event in edges:
                    self.assertFalse(event["repeat"])
                    self.assertEqual(event["send_user_command"]["payload"]["phase"], "press" if field == "to" else "release")
                    self.assertTrue(any("session" in c.get("expression", "") for c in event["conditions"]))
                if "Floating Mouse clutch" not in rule["description"]:
                    observed.append(item)
                    self.assertGreater(len(item["to"]), 1)
                    self.assertGreaterEqual(len(item["to_after_key_up"]), 1)
                    self.assertFalse(any("floating_corsair1" in c.get("expression", "") for c in item["conditions"]))
        self.assertEqual(len(observed), 4)
        self.assertNotIn("agentic_mouse_floating_clutch", json.dumps(document["rules"][0]))
