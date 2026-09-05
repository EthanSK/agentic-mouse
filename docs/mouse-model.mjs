import * as THREE from "three";
import { GLTFLoader } from "./lib/loaders/GLTFLoader.js";
import { DRACOLoader } from "./lib/loaders/DRACOLoader.js";

const decoder = new DRACOLoader();
decoder.setDecoderPath(new URL("./lib/draco/", import.meta.url).href);
decoder.setWorkerLimit(2);
const loader = new GLTFLoader().setDRACOLoader(decoder);
const assets = new Map();

/** Load the authored hardware once; derive every physical-key action from the native export. */
export async function createMouseModel(hand, source) { // Ethan rejected generic rounded-shell substitutes: preserve the separate reference-modelled Naga and Scimitar assets. (Codex task: 01a06ee5-4aa0-7a61-a029-704e5c44a8f2)
  if (!assets.has(hand)) assets.set(hand, loader.loadAsync(new URL(`./models/${hand}.glb?v=__SITE_VERSION__`, import.meta.url).href));
  const asset = await assets.get(hand);
  const group = asset.scene.clone(true);
  const side = hand === "razer" ? 1 : -1;
  const keys = new Map();
  const pickables = [];
  let speech;
  group.traverse((object) => {
    if (object.userData.button) {
      const control = source.modes.default.controls.find((item) => item.printed === object.userData.button);
      if (!control) throw new Error(`No native physical crosswalk for ${hand} ${object.userData.button}`);
      object.userData.cell = control.cell;
      object.userData.rest = object.position.clone();
      object.traverse((part) => {
        if (!part.isMesh) return;
        part.userData.cell = control.cell;
        part.material = part.material.clone();
        if (part.material.name.startsWith("Keycaps") || part.material.name.startsWith("Textured keycaps")) {
          object.material = part.material;
          object.userData.color = part.material.color.clone();
        }
      });
      keys.set(control.cell, object);
    }
    if (object.userData.speech === true) {
      speech = object;
      object.traverse((part) => { part.userData.speech = true; });
    }
    if (object.isMesh) pickables.push(object);
  });
  if (keys.size !== 12 || !speech) throw new Error(`Incomplete ${hand} hardware model`);
  return { group, keys, speech, pickables, side };
}

/** Light both chapters as one restrained product studio: feathered low-radiance diffusers over a dark table. */
export function lightStudio(renderer, scene, exposure = 1) { // RoomEnvironment's small 50–100× panels reflected as chrome-like white rectangles on the near-black dielectric shells; broad soft sources at a few times white let graphite ABS read as satin plastic instead.
  renderer.toneMapping = THREE.NeutralToneMapping; // Khronos neutral keeps the green/yellow accents and white emblems truthful where ACES desaturated and cooled them.
  renderer.toneMappingExposure = exposure;
  const studio = new THREE.Scene();
  studio.add(backdrop(40));
  studio.add(softbox([-7, 12, 9], 18, 12, 12, [1, .97, .93])); // Key: one large, faintly warm overhead diffuser drapes a single soft highlight across the palm.
  studio.add(softbox([9, -1, 11], 16, 10, 2.2, [1, 1, 1])); // Fill: a faint card behind the camera lifts the click plates without a front glare.
  studio.add(softbox([10, 6, -8], 4, 16, 7, [.9, .95, 1])); // Edge: a cool strip behind the right shoulder separates the shell from the near-black chapter.
  studio.add(softbox([-2, 9, -11], 18, 4, 3.5, [1, 1, 1])); // Back: a low rear strip draws the shoulder line without adding a second hot spot.
  const pmrem = new THREE.PMREMGenerator(renderer);
  scene.environment = pmrem.fromScene(studio, .035).texture;
  scene.environmentIntensity = .65;
  pmrem.dispose();
  studio.traverse((object) => { object.geometry?.dispose(); object.material?.dispose(); });
  const key = new THREE.DirectionalLight(0xfff2e4, .7);
  key.position.set(-4, 8, 6);
  scene.add(key);
  const edge = new THREE.DirectionalLight(0xdae6ff, .85);
  edge.position.set(6, 3, -5);
  scene.add(edge);
}

/** A dark table rising through a neutral horizon to a soft ceiling, so undersides stay dark and tops lift. */
function backdrop(radius) {
  const geometry = new THREE.SphereGeometry(radius, 48, 32);
  const position = geometry.attributes.position;
  const colors = new Float32Array(position.count * 3);
  const floor = new THREE.Color(.014, .013, .012), horizon = new THREE.Color(.07, .071, .075), ceiling = new THREE.Color(.34, .35, .38), color = new THREE.Color();
  for (let i = 0; i < position.count; i++) {
    const t = position.getY(i) / radius;
    color.lerpColors(horizon, t < 0 ? floor : ceiling, THREE.MathUtils.smoothstep(Math.abs(t), 0, 1));
    colors.set([color.r, color.g, color.b], i * 3);
  }
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  return new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide }));
}

/** A feathered oval diffuser aimed at the hardware; hard panel edges were the white rectangles across the palms. */
function softbox([x, y, z], width, height, peak, [r, g, b]) {
  const geometry = new THREE.PlaneGeometry(width, height, 24, 24);
  const position = geometry.attributes.position;
  const colors = new Float32Array(position.count * 3);
  for (let i = 0; i < position.count; i++) {
    const radial = Math.hypot(position.getX(i) * 2 / width, position.getY(i) * 2 / height);
    const glow = peak * Math.max(0, 1 - radial * radial) ** 1.4;
    colors.set([glow * r, glow * g, glow * b], i * 3);
  }
  geometry.setAttribute("color", new THREE.Float32BufferAttribute(colors, 3));
  const panel = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.DoubleSide, blending: THREE.AdditiveBlending, transparent: true, depthWrite: false }));
  panel.position.set(x, y, z);
  panel.lookAt(0, 0, 0); // Additive over the backdrop, so the feathered rim blends into the room instead of leaving black corners.
  return panel;
}
