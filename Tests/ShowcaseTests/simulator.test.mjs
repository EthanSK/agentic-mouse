import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { MouseSimulator } from "../../docs/simulator.mjs";

const map = JSON.parse(
  readFileSync(
    new URL("../../.build/site/simulator-data.json", import.meta.url),
  ),
);
const enter = (simulator, destination) => {
  const control = simulator.mode.controls.find(
    (item) => item.next === destination,
  );
  assert.ok(control, `No route from ${simulator.state.mode} to ${destination}`);
  simulator.press(control.cell, 0);
};

test("native graph has complete physical grids and resolvable destinations for both hands", () => {
  for (const source of Object.values(map.sources)) {
    assert.deepEqual(
      [...source.rows.flat()].sort((a, b) => a - b),
      Array.from({ length: 12 }, (_, index) => index + 1),
    );
    for (const mode of [
      ...Object.values(source.modes),
      ...Object.values(source.defaults),
    ]) {
      assert.equal(mode.controls.length, 12);
      assert.equal(
        new Set(mode.controls.map((control) => control.printed)).size,
        12,
      );
      for (const control of mode.controls) {
        if (control.next) assert.ok(source.modes[control.next], control.next);
        assert.match(control.color, /^#[0-9a-f]{6}$/);
      }
    }
    for (const app of map.apps)
      assert.ok(source.modes[app.id] && source.defaults[app.id]);
  }
});

test("buttons enter Utility, Keys, Keypad and exit to the real Default map", () => {
  for (const hand of Object.keys(map.sources)) {
    const simulator = new MouseSimulator(map);
    simulator.chooseHand(hand);
    enter(simulator, "utility");
    enter(simulator, "keys");
    enter(simulator, "keypad");
    enter(simulator, "default");
    assert.equal(simulator.mode.title, "Default mode");
  }
});

test("automatic app mode follows changes but a manual selection and its Chrome child stay locked", () => {
  const simulator = new MouseSimulator(map);
  enter(simulator, "codex");
  assert.equal(simulator.state.followsApp, true);
  simulator.chooseApp("chrome");
  assert.equal(simulator.state.mode, "chrome");
  enter(simulator, "websites");
  enter(simulator, "chrome");
  assert.equal(simulator.state.followsApp, true);
  enter(simulator, "default");
  enter(simulator, "utility");
  enter(simulator, "apps");
  enter(simulator, "chrome");
  assert.equal(simulator.state.followsApp, false);
  enter(simulator, "websites");
  enter(simulator, "chrome");
  simulator.chooseApp("codex");
  assert.equal(simulator.state.mode, "chrome");
  assert.equal(simulator.state.followsApp, false);
});

test("left/right modes and Default legend toggles remain independent", () => {
  const simulator = new MouseSimulator(map);
  const legendCell = simulator.mode.controls.find(
    (item) => item.effect === "toggleLegend",
  ).cell;
  simulator.press(legendCell);
  enter(simulator, "utility");
  simulator.chooseHand("razer");
  assert.equal(simulator.state.mode, "default");
  assert.equal(simulator.state.legend, true);
  enter(simulator, "keys");
  simulator.chooseHand("corsair");
  assert.equal(simulator.state.mode, "utility");
  enter(simulator, "default");
  assert.equal(simulator.state.legend, false);
});

test("both native exit cells leave every app child", () => {
  for (const app of map.apps) {
    const exits = map.sources.corsair.modes[app.id].controls.filter(
      (item) => item.next === "default",
    );
    assert.equal(exits.length, 2, app.id);
    for (const control of exits) {
      const simulator = new MouseSimulator(map);
      simulator.chooseMode(app.id);
      simulator.press(control.cell);
      assert.equal(simulator.state.mode, "default");
    }
  }
});

test("a held wheel uses native direction labels and suppresses repeat one-shot actions", () => {
  const simulator = new MouseSimulator(map);
  simulator.chooseMode("utility");
  const control = simulator.mode.controls.find(
    (item) => item.wheel?.oncePerHold && item.wheel.up && item.wheel.down,
  );
  simulator.press(control.cell);
  simulator.wheel("up");
  assert.equal(simulator.state.output, control.wheel.up);
  simulator.wheel("down");
  assert.equal(simulator.state.output, "Release and hold again");
  simulator.release();
  simulator.hold(control.cell);
  simulator.wheel("down");
  assert.equal(simulator.state.output, control.wheel.down);
});

test("keypad cycles native letters, commits after timeout, supports digit holds and Backspace", () => {
  const simulator = new MouseSimulator(map);
  simulator.chooseMode("keypad");
  const abc = simulator.mode.controls.find(
    (item) => item.keypad?.cycle.join("") === "abc",
  );
  simulator.press(abc.cell, 0);
  simulator.press(abc.cell, 200);
  assert.equal(simulator.state.output, "B");
  simulator.tick(200 + map.keypadTimeout);
  assert.equal(simulator.state.text, "B");
  simulator.hold(abc.cell);
  assert.equal(simulator.state.text, `B${abc.keypad.digit}`);
  const backspace = simulator.mode.controls.find(
    (item) => item.keypad?.tap?.backspace,
  );
  simulator.press(backspace.cell, 2000);
  assert.equal(simulator.state.text, "B");
});

test("changing hands does not strand the first mouse's pending letter", () => {
  const simulator = new MouseSimulator(map);
  simulator.chooseMode("keypad");
  simulator.press(2, 0);
  simulator.chooseHand("razer");
  simulator.tick(map.keypadTimeout);
  assert.equal(simulator.states.corsair.text, "A");
  assert.equal(simulator.states.razer.text, "");
});

test("changing current app cancels pending text and held controls", () => {
  const simulator = new MouseSimulator(map);
  simulator.chooseMode("keypad");
  simulator.press(2, 0);
  simulator.chooseApp("chrome");
  simulator.tick(map.keypadTimeout);
  assert.equal(simulator.state.text, "");
  assert.equal(simulator.state.held, null);
});

test("reset restores only the selected mouse and leaves the other mouse's mode intact", () => {
  const simulator = new MouseSimulator(map);
  enter(simulator, "keys");
  simulator.chooseHand("razer");
  enter(simulator, "utility");
  simulator.reset();
  assert.equal(simulator.state.mode, "default");
  assert.equal(simulator.states.corsair.mode, "keys");
});
