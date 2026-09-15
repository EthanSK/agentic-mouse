import importlib.util
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("generator", ROOT / "Scripts/generate-karabiner.py")
generator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(generator)


class VSCodeHoldTests(unittest.TestCase):
    def setUp(self):
        self.variables = {}
        self.now = 10000
        self.keys = []
        self.feedback = []
        self.frontmost = True

    def expression(self, value):
        value = value.replace("system.now.milliseconds", str(self.now))
        value = re.sub(r"agentic_mouse_\w+", lambda m: str(self.variables.get(m[0], 0)), value)
        return eval(value, {"__builtins__": {}}, {})

    def matches(self, conditions):
        for condition in conditions:
            kind = condition["type"]
            if kind.startswith("variable_"):
                matches = self.variables.get(condition["name"], 0) == condition["value"]
            elif kind.startswith("expression_"):
                matches = bool(self.expression(condition["expression"]))
            elif kind == "frontmost_application_if":
                matches = self.frontmost
            else:
                self.fail(f"Unsupported condition: {kind}")
            if kind.endswith("unless"):
                matches = not matches
            if not matches:
                return False
        return True

    def events(self, events):
        for event in events:
            if not self.matches(event.get("conditions", [])):
                continue
            if "set_variable" in event:
                variable = event["set_variable"]
                self.variables[variable["name"]] = variable.get("value") if "value" in variable else self.expression(variable["expression"])
            if "key_code" in event:
                self.assertIs(event["repeat"], False)
                if event["key_code"] in ("f14", "f15", "f20"):
                    self.feedback.append((event["key_code"], event["modifiers"]))
                else:
                    self.keys.append(event["key_code"])

    def rule(self, source, cell, chord=False):
        action = "vscode-go-to-next-change" if cell == 8 else "vscode-go-to-previous-change"
        if chord:
            action = f"vscode-stage-{'next' if cell == 8 else 'previous'}-while-{source}-held"
        return generator.vscode_hold_templates({"id": f"{source}-vscode-side-{cell:02d}", "action": action})[0]

    def press(self, source, cell, duration, delayed_timer=False):
        rule = self.rule(source, cell)
        if not self.matches(rule["conditions"]):
            return
        self.events(rule["to"])
        self.now += duration
        if duration >= 200 or delayed_timer:
            self.events(rule["to_if_held_down"])
        if duration < 200:
            self.events(rule["to_if_alone"])
        self.events(rule["to_after_key_up"])

    def test_short_release_and_every_long_release_are_independent(self):
        for source in ("corsair", "razer"):
            for cell, navigation, stage in ((5, "f17", "f19"), (8, "f13", "f18")):
                self.setUp()
                for duration in (199, 200, 400, 201):
                    self.press(source, cell, duration)
                self.assertEqual(self.keys, [navigation, navigation, stage, navigation, stage, navigation, stage])

    def test_original_short_duration_overrides_a_premature_hold_timer(self):
        for _ in range(20):
            self.press("corsair", 8, 60, delayed_timer=True)
        self.assertEqual(self.keys, ["f13"] * 20)
        self.assertEqual([key for key, _ in self.feedback], ["f20", "f14", "f15"] * 20)

    def test_ready_is_feedback_only_and_release_clears_each_mouse(self):
        for source in ("corsair", "razer"):
            for cell, navigation, stage in ((5, "f17", "f19"), (8, "f13", "f18")):
                self.setUp()
                rule = self.rule(source, cell)
                self.assertEqual(rule["parameters"]["basic.to_if_held_down_threshold_milliseconds"], 200)
                self.assertEqual(rule["parameters"]["basic.to_if_alone_timeout_milliseconds"], 200)
                self.events(rule["to"])
                self.assertEqual(self.feedback, [])
                self.events(rule["to_if_held_down"])
                self.assertEqual(self.keys, [navigation])
                self.events(rule["to_after_key_up"])
                self.assertEqual(self.keys, [navigation, stage])
                self.assertEqual([key for key, _ in self.feedback], ["f20", "f15"])
                expected = ["left_command", "left_shift"] if source == "razer" else ["left_control", "left_option", "left_command"]
                self.assertTrue(all(modifiers == expected for key, modifiers in self.feedback if key != "f14"))

    def test_ready_does_not_depend_on_same_list_pending_mutation(self):
        for source in ("corsair", "razer"):
            for cell in (5, 8):
                held = f"agentic_mouse_{source}_vscode_hold_{cell}"
                ready = self.rule(source, cell)["to_if_held_down"][1]
                self.assertFalse(any(condition.get("name") == held for condition in ready.get("conditions", [])))

    def test_feedback_cannot_complete_voiceink_modifier_chord_in_any_order(self):
        # A full Hyper chord looked distinct but Karabiner briefly pressed
        # Control+Shift+Option before Command, starting VoiceInk (sourcePID 0).
        voiceink = {"left_control", "left_shift", "left_option"}
        for source in ("corsair", "razer"):
            for cell in (5, 8):
                self.setUp()
                self.press(source, cell, 600)
                self.assertTrue(self.feedback)
                for _, modifiers in self.feedback:
                    self.assertFalse(voiceink.issubset(modifiers))

    def test_undo_consumes_both_buttons_before_or_after_hold_threshold(self):
        for source in ("corsair", "razer"):
            for cell in (5, 8):
                for long in (False, True):
                    self.setUp()
                    nav = self.rule(source, cell)
                    chord = self.rule(source, cell, chord=True)
                    self.events(nav["to"])
                    if long:
                        self.events(nav["to_if_held_down"])
                    self.assertEqual(self.keys, ["f13" if cell == 8 else "f17"])
                    self.assertTrue(self.matches(chord["conditions"]))
                    self.events(chord["to"])
                    self.events(chord["to"])
                    self.events(nav["to_if_held_down"])
                    self.events(nav["to_if_alone"])
                    self.events(nav["to_after_key_up"])
                    self.assertEqual(self.keys, ["f13" if cell == 8 else "f17", "f16"])
                    self.assertFalse(self.matches(chord["conditions"]))

    def test_other_mouse_cannot_undo_and_release_leaves_no_late_window(self):
        self.events(self.rule("corsair", 8)["to"])
        self.assertFalse(self.matches(self.rule("razer", 8, chord=True)["conditions"]))
        self.events(self.rule("corsair", 8)["to_after_key_up"])
        self.assertFalse(self.matches(self.rule("corsair", 8, chord=True)["conditions"]))

    def test_legacy_flag_disables_both_new_native_gestures(self):
        self.variables[generator.VSCODE_LEGACY_STAGE_FLAG] = 1
        self.press("corsair", 8, 550)
        self.variables["agentic_mouse_corsair_vscode_hold_8"] = 1
        self.assertFalse(self.matches(self.rule("corsair", 8, chord=True)["conditions"]))
        self.assertEqual(self.keys, [])

    def test_other_frontmost_app_cannot_receive_release_stage(self):
        rule = self.rule("corsair", 8)
        self.events(rule["to"])
        self.frontmost = False
        self.events(rule["to_if_held_down"])
        self.events(rule["to_after_key_up"])
        self.assertEqual(self.keys, ["f13"])
