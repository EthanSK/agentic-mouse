import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const site = new URL("../../.build/site/", import.meta.url);
const map = JSON.parse(readFileSync(new URL("simulator-data.json", site)));

test("published mouse assets expose every native printed button and the speech control", () => {
  for (const hand of Object.keys(map.sources)) {
    const bytes = readFileSync(new URL(`models/${hand}.glb`, site));
    assert.equal(bytes.toString("ascii", 0, 4), "glTF");
    assert.equal(bytes.readUInt32LE(4), 2);
    assert.equal(bytes.readUInt32LE(8), bytes.length);
    const gltf = JSON.parse(bytes.toString("utf8", 20, 20 + bytes.readUInt32LE(12)));
    const buttons = gltf.nodes.filter((node) => node.extras?.button);
    assert.deepEqual(
      buttons.map((node) => node.extras.button).sort((a, b) => a - b),
      map.sources[hand].modes.default.controls.map((control) => control.printed).sort((a, b) => a - b),
    );
    assert.equal(gltf.nodes.filter((node) => node.extras?.speech === true).length, 1);
    for (const button of buttons) assert.ok(button.children?.length, "A physical button must contain visible pickable geometry");
    assert.ok(gltf.extensionsRequired.includes("KHR_draco_mesh_compression"));
    assert.ok(bytes.length < 2_000_000, "Keep each interactive mouse within the mobile asset budget");
    assert.deepEqual(bytes, readFileSync(new URL(`../../docs/models/${hand}.glb`, import.meta.url)));
  }
  const decoder = readFileSync(new URL("lib/draco/draco_decoder.wasm", site));
  assert.deepEqual([...decoder.subarray(0, 4)], [0, 97, 115, 109]);
});
