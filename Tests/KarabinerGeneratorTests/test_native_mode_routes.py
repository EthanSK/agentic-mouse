"""Exercise the admitted transport route, against the real native mode graph.

Checking that a key-up exists somewhere is insufficient: a higher-priority
page exception can match instead and swallow it, as Utility Zoom did.
"""
import ast
import json
import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOW = 1_000_000


def expression(value, variables):
    value = value.replace("system.now.milliseconds", str(NOW))
    tree = ast.parse(value, mode="eval")

    def read(node):
        if isinstance(node, ast.Expression):
            return read(node.body)
        if isinstance(node, ast.Constant):
            return node.value
        if isinstance(node, ast.Name):
            return variables.get(node.id, 0)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            return read(node.left) + read(node.right)
        if isinstance(node, ast.BoolOp):
            items = [bool(read(n)) for n in node.values]
            return all(items) if isinstance(node.op, ast.And) else any(items)
        if isinstance(node, ast.Compare) and len(node.ops) == 1:
            a, b = read(node.left), read(node.comparators[0])
            return {ast.Eq: lambda: a == b, ast.Gt: lambda: a > b,
                    ast.LtE: lambda: a <= b}[type(node.ops[0])]()
        raise AssertionError(f"Unsupported generated expression: {ast.dump(node)}")
    return bool(read(tree))


def admitted(conditions, variables, device, bundle):
    for c in conditions:
        kind = c["type"]
        if kind.startswith("expression_"):
            match = expression(c["expression"], variables)
        elif kind.startswith("device_"):
            match = any(all(device.get(k) == v for k, v in d.items()) for d in c["identifiers"])
        elif kind.startswith("frontmost_application_"):
            match = any(re.search(pattern, bundle) for pattern in c["bundle_identifiers"])
        elif kind.startswith("variable_"):
            match = variables.get(c["name"], 0) == c["value"]
        else:
            raise AssertionError(f"Unsupported generated condition: {c}")
        if match != kind.endswith("_if"):
            return False
    return True


class NativeModeRouteTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Inert native exporter: no hardware, app activation or command posting.
        audit = json.loads(subprocess.check_output(
            ["swift", "run", "agentic-mouse-site", "--routing-audit"], cwd=ROOT, stderr=subprocess.DEVNULL))
        cls.native, cls.pages, cls.bundles = audit["map"], audit["pages"], audit["appBundles"]
        cls.generated = json.loads((ROOT / "Karabiner/generated/agentic-mouse-runtime.json").read_text())
        cls.bindings = json.loads((ROOT / "Karabiner/bindings/bindings.json").read_text())

    def test_each_native_page_keeps_held_releases_and_navigation_in_sync(self):
        by_id = {b["id"]: b for b in self.bindings["bindings"]}
        checked = 0
        total = 0
        for source, native in self.native["sources"].items():
            metadata = self.bindings["modePicker"]
            page_var = metadata["pageVariablesBySource"][source]
            selection_var = metadata["appSelectionVariablesBySource"][source]
            definitions = [(mode, definition, None) for mode, definition in native["modes"].items()]
            definitions += [("default", definition, self.bundles[app]) for app, definition in native["defaults"].items()]
            for mode, definition, default_bundle in definitions:
                page = self.pages.get(mode, self.pages["appSpecific"])
                manual_selection = 1 if mode == "codex" else 3 if mode in ("chrome", "websites") else 4 if mode == "vsCode" else 2
                contexts = [(manual_selection, "test.foreground", "manual")]
                if default_bundle:
                    contexts = [(0, default_bundle, "default-app-context")]
                if mode in self.bundles or mode == "websites":
                    contexts.append((0, self.bundles.get(mode, self.bundles["chrome"]), "automatic"))
                for selection, bundle, journey in contexts:
                    for control in definition["controls"]:
                        cell = control["cell"]
                        binding = by_id[metadata["bindingsBySource"][source][cell - 1]]
                        device = next(c["identifiers"][0] for c in binding["conditions"] if c["type"] == "device_if")
                        variables = {"agentic_mouse_session_unlocked_expires_at": NOW + 3000,
                                     metadata["leaseVariablesBySource"][source]: NOW + 12000 if page else 0,
                                     page_var: page, selection_var: selection}
                        candidates = [m for r in self.generated["rules"] for m in r["manipulators"]
                                      if m["from"] == binding["from"]
                                      and admitted(m.get("conditions", []), variables, device, bundle)]
                        with self.subTest(source=source, mode=mode, journey=journey, cell=cell):
                            self.assertTrue(candidates, "No route for a native control")
                            route = candidates[0]  # Karabiner takes the first matching manipulator.
                            total += 1
                            after = dict(variables)
                            for e in route["to"]:
                                if "set_variable" in e:
                                    v = e["set_variable"]
                                    after[v["name"]] = v.get("value", NOW + 1200)
                            destination = control.get("next")
                            if destination and destination != "default":
                                self.assertEqual(after[page_var], self.pages.get(destination, self.pages["appSpecific"]),
                                                 f"Native {mode} → {destination} leaves transport on the wrong page")
                                if mode == "apps":
                                    self.assertEqual(after[selection_var], 1 if destination == "codex" else 3 if destination == "chrome" else 4 if destination == "vsCode" else 2)
                            press = [e["send_user_command"]["payload"] for e in route["to"]
                                     if "send_user_command" in e and admitted(e.get("conditions", []), after, device, bundle)]
                            release = [e["send_user_command"]["payload"] for e in route.get("to_after_key_up", [])
                                       if "send_user_command" in e and admitted(e.get("conditions", []), after, device, bundle)]
                            if page and (not destination or (mode == "codex" and cell == 2)):
                                for p in press:
                                    if p.get("action") == "select":
                                        self.assertIn({**p, "phase": "release"}, release,
                                                      "Stable native select route loses its physical release")
                            if mode == "keys" and cell == 2:
                                self.assertEqual(route["to"][-1]["key_code"], "left_shift")
                                self.assertIs(route["to"][-1]["repeat"], True,
                                              "Native Shift must remain held until the physical key-up")
                            if mode == "default" and cell in (10, 11):
                                held = [e for e in route["to"] if e.get("key_code") == "left_command"]
                                self.assertEqual(len(held), 1)
                                self.assertIs(held[0].get("repeat", True), True,
                                              "Native Command uses Karabiner's physical-release lifecycle")
                            if control.get("wheel"):
                                self.assertEqual(after[page_var], page, "A held wheel control unexpectedly changes page")
                                if page:
                                    expected = {"command": "agentic_mouse_mode_picker", "action": "select",
                                                "source": source, "physical_cell": cell, "phase": "press"}
                                else:
                                    expected = {"command": "agentic_mouse_wheel_chord", "control": control["wheel"]["id"],
                                                "source": source, "phase": "press"}
                                self.assertIn(expected, press)
                                self.assertIn({**expected, "phase": "release"}, release,
                                              "The actual admitted hold route has no matching key-up")
                                checked += 1
        self.assertGreaterEqual(checked, 40, "Audit accidentally omitted held controls")
        print(f"Native route audit: {total} source/page/context/cell cases; {checked} wheel hold lifetimes")
