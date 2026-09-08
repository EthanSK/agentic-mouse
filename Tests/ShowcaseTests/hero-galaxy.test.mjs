import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { runInNewContext } from "node:vm";
import * as THREE from "../../docs/lib/three.module.min.js";

/** Exercise the real header controller with a manual browser clock and a recording renderer. */
function createHarness() {
  const frames = new Map();
  let frameID = 0, now = 0, draws = 0, uniforms;
  const canvas = Object.assign(new EventTarget(), { style: {} });
  const hero = Object.assign(new EventTarget(), {
    clientWidth: 1200, clientHeight: 800,
    querySelector: () => canvas,
    getBoundingClientRect: () => ({ left: 0, top: 80 }),
  });
  const document = Object.assign(new EventTarget(), { hidden: false });
  const window = new EventTarget();
  const reduced = Object.assign(new EventTarget(), { matches: false });
  let intersection, resize;
  const source = readFileSync(new URL("../../docs/hero-galaxy.mjs", import.meta.url), "utf8")
    .replace('import * as THREE from "three";', "").replace("export function", "function");
  runInNewContext(`${source}\ncreateHeroGalaxy(hero);`, {
    THREE: { ...THREE, WebGLRenderer: class {
      setPixelRatio() {}
      getPixelRatio() { return 1.25; }
      setSize() {}
      render(scene) { draws++; uniforms = scene.children[0].material.uniforms; }
    } },
    hero, document, window, devicePixelRatio: 2,
    matchMedia: query => query.includes("reduced-motion") ? reduced : { matches: false },
    ResizeObserver: class { constructor(callback) { resize = callback; } observe() {} },
    IntersectionObserver: class { constructor(callback) { intersection = callback; } observe() {} },
    requestAnimationFrame: callback => { frames.set(++frameID, callback); return frameID; },
    cancelAnimationFrame: id => frames.delete(id),
    performance: { now: () => now },
  });
  function step(milliseconds = 40) {
    now += milliseconds;
    const pending = [...frames.values()];
    frames.clear();
    pending.forEach(callback => callback(now));
  }
  function move(x, y, pointerType = "mouse") {
    hero.dispatchEvent(Object.assign(new Event("pointermove"), { clientX: x, clientY: y, pointerType }));
  }
  resize();
  intersection([{ isIntersecting: true }]);
  step();
  return {
    step, move, canvas, hero, document, window, reduced,
    get draws() { return draws; }, get uniforms() { return uniforms; },
    get pending() { return frames.size; },
    intersect: value => intersection([{ isIntersecting: value }]),
  };
}

test("pointer input moves the local field without pausing its animation", () => {
  const h = createHarness();
  h.move(800, 480);
  h.step();
  const start = h.uniforms.time.value;
  for (let i = 0; i < 20; i++) { h.move(800 + i * 4, 480); h.step(17); }
  assert.ok(h.uniforms.time.value > start + .3, "Pointer movement must not trigger the mouse models' six-second idle pause");
  assert.ok(h.uniforms.pointer.value.z > .9);
  assert.equal(h.uniforms.pointer.value.x, (876 - 600) * 2 / 800);
  assert.equal(h.uniforms.pointer.value.y, 0, "Account for the hero's position below navigation");
  assert.ok([...h.uniforms.trailBirth.value].every(value => value >= start), "The GPU receives a bounded recent wake");
  h.hero.dispatchEvent(new Event("pointerleave"));
  for (let i = 0; i < 50; i++) h.step();
  assert.ok(h.uniforms.pointer.value.z < .001);
  assert.ok([...h.uniforms.trailBirth.value].every(value => h.uniforms.time.value - value > 1.4));
});

test("hidden, off-screen, reduced-motion and lost-context headers stop rendering", () => {
  const h = createHarness();
  for (const pause of ["offscreen", "hidden", "context"]) {
    const before = h.draws;
    if (pause === "offscreen") h.intersect(false);
    if (pause === "hidden") { h.document.hidden = true; h.document.dispatchEvent(new Event("visibilitychange")); }
    if (pause === "context") h.canvas.dispatchEvent(new Event("webglcontextlost", { cancelable: true }));
    h.move(900, 450);
    h.step(10000);
    assert.equal(h.draws, before);
    assert.equal(h.pending, 0);
    const time = h.uniforms.time.value;
    if (pause === "offscreen") h.intersect(true);
    if (pause === "hidden") { h.document.hidden = false; h.document.dispatchEvent(new Event("visibilitychange")); }
    if (pause === "context") h.canvas.dispatchEvent(new Event("webglcontextrestored"));
    h.step();
    assert.equal(h.uniforms.time.value, time, "Do not catch up for time spent suspended");
  }
  h.reduced.matches = true;
  h.reduced.dispatchEvent(new Event("change"));
  h.step();
  const before = h.draws;
  h.move(800, 500);
  h.step(10000);
  assert.equal(h.draws, before);
  assert.equal(h.pending, 0);
  assert.equal(h.uniforms.pointer.value.z, 0);
  assert.ok([...h.uniforms.trailBirth.value].every(value => value === -10));
});

test("touch and scroll preserve normal page input and clear stale strokes", () => {
  const h = createHarness();
  h.move(900, 500, "touch");
  h.step();
  assert.equal(h.uniforms.pointer.value.z, 0);
  h.move(900, 500);
  h.step();
  h.move(940, 500);
  h.step();
  const scroll = new Event("scroll", { cancelable: true });
  h.window.dispatchEvent(scroll);
  h.step();
  assert.equal(scroll.defaultPrevented, false);
  assert.equal(h.uniforms.pointer.value.z, 0);
  assert.ok([...h.uniforms.trailBirth.value].every(value => value === -10));
});

test("high-frequency pointer events stay within the draw budget", () => {
  const h = createHarness();
  let before = h.draws;
  for (let i = 0; i < 1000; i++) h.step(1);
  assert.ok(h.draws - before <= 31, "Idle rendering stays near 30 fps");
  before = h.draws;
  for (let i = 0; i < 1000; i++) { h.move(600 + i % 200, 500); h.step(1); }
  assert.ok(h.draws - before <= 63, "Pointer events cannot bypass the 60 fps interaction cap");
  assert.ok(h.draws - before >= 55, "Pointer feedback uses the higher interaction rate");
});
