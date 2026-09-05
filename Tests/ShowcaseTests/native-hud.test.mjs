import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { MouseSimulator } from "../../docs/simulator.mjs";
import { hudPresentation } from "../../docs/native-hud.mjs";

const map = JSON.parse(readFileSync(new URL("../../.build/site/simulator-data.json", import.meta.url)));

test("the native HUD preserves each hand's physical order and printed repair markers", () => {
  const simulator = new MouseSimulator(map);
  for (const hand of Object.keys(map.sources)) {
    simulator.chooseHand(hand);
    for (const mode of Object.keys(map.sources[hand].modes)) {
      simulator.chooseMode(mode);
      const hud = hudPresentation(simulator);
      assert.deepEqual(hud.cards.map((card) => card.cell), map.sources[hand].rows.flat());
      for (const card of hud.cards) {
        const control = simulator.control(card.cell);
        assert.equal(card.printed, control.printed);
        assert.equal(card.label.includes("❌"), control.reportedBroken);
        assert.equal(card.title, control.title);
        assert.match(card.fill, /^#[0-9a-f]{6}$/);
        if (control.destinationColor) {
          assert.equal(card.fill, control.destinationColor);
          assert.equal(card.border, control.destinationColor);
          assert.equal(card.fillOpacity, 1);
        }
        if (control.appIcon) {
          const icon = readFileSync(new URL(`../../docs/assets/apps/${control.appIcon}.png`, import.meta.url));
          assert.equal(icon.readUInt32BE(16), 128);
          assert.equal(icon.readUInt32BE(20), 128);
        }
      }
    }
  }
});

test("a hidden Default legend stays hidden after a mode exits, independently for each mouse", () => {
  const simulator = new MouseSimulator(map);
  simulator.press(10);
  assert.equal(hudPresentation(simulator).visible, false);
  simulator.press(9);
  assert.equal(hudPresentation(simulator).title, "Keys mode");
  assert.equal(hudPresentation(simulator).visible, true);
  simulator.press(10);
  assert.equal(hudPresentation(simulator).visible, false);
  simulator.chooseHand("razer");
  assert.equal(hudPresentation(simulator).visible, true);
});

test("entering a mode clears the old selection and feedback; actions highlight only their native card", () => {
  const simulator = new MouseSimulator(map);
  simulator.press(7);
  assert.equal(hudPresentation(simulator).cards.some((card) => card.selected), false);
  simulator.press(2);
  let hud = hudPresentation(simulator);
  assert.equal(hud.title, "Codex mode");
  assert.equal(hud.feedback, null);
  assert.equal(hud.cards.some((card) => card.selected), false);
  simulator.press(5);
  hud = hudPresentation(simulator);
  assert.deepEqual(hud.cards.filter((card) => card.selected).map((card) => card.cell), [5]);
  assert.equal(hud.status, simulator.control(5).effect);
  simulator.press(10);
  assert.equal(hudPresentation(simulator).feedback, null);
});

test("Keypad HUD shows the native cycle, pending letter and case change after commit", () => {
  const simulator = new MouseSimulator(map);
  simulator.chooseMode("keypad");
  simulator.press(2, 0);
  simulator.press(2, 100);
  let hud = hudPresentation(simulator);
  const card = hud.cards.find((item) => item.cell === 2);
  assert.equal(hud.style, "keypad");
  assert.deepEqual(card.cycle, ["A", "B", "C"]);
  assert.equal(card.activeCycleIndex, 1);
  assert.equal(hud.status, "B  ·  tap 2 of 3");
  assert.equal(hud.cards.find((item) => item.cell === 1).cycle.length, simulator.control(1).keypad.cycle.length);
  simulator.tick(100 + map.keypadTimeout);
  hud = hudPresentation(simulator);
  assert.equal(hud.status, "Ready");
  assert.equal(hud.shift, "abc");
  assert.deepEqual(hud.cards.find((item) => item.cell === 2).cycle, ["a", "b", "c"]);
  assert.equal(hud.cards.some((item) => item.activeCycleIndex !== null), false);
});
