import * as THREE from "three";
import { MouseSimulator } from "./simulator.mjs?v=__SITE_VERSION__";
import { createNativeHUD } from "./native-hud.mjs?v=__SITE_VERSION__";
import { createHeroMouse } from "./hero-mice.mjs?v=__SITE_VERSION__";

const stage = document.querySelector("#room-stage");
const canvas = document.querySelector("#room-canvas");
const detail = document.querySelector("#room-detail");
const reduced = matchMedia("(prefers-reduced-motion: reduce)");
const hotspots = [...document.querySelectorAll(".room-hotspots [data-topic]")];
const hotspotWidths = new Map();
const view = { zoom: 0, x: 0, y: 0, panX: 0, panY: 0 };
const target = { zoom: 0, x: 0, y: 0, panX: 0, panY: 0 };
let renderer, camera, scene, photo, frame = 0, width = 0, height = 0, lastFrame = 0;
let focusPoint = { x: -.7, y: .2 }, pointer = { x: 0, y: 0 };
const roomWidth = 20, roomHeight = 20 * 941 / 1671;
const point = new THREE.Vector3();

/** Render the camera only while it is moving; the photograph keeps its original proportions. */
function draw(now = 0) {
  frame = 0;
  if (!renderer || !width || !height || document.hidden) return;
  const elapsed = Math.min(now - lastFrame, 50);
  lastFrame = now;
  const ease = reduced.matches ? 1 : 1 - Math.exp(-elapsed / 65);
  let moving = false;
  for (const key of ["zoom", "x", "y", "panX", "panY"]) {
    view[key] += (target[key] - view[key]) * ease;
    if (Math.abs(target[key] - view[key]) > .003) moving = true;
    else view[key] = target[key];
  }
  const distance = Math.max(roomHeight / 2, roomWidth / (2 * camera.aspect)) / Math.tan(THREE.MathUtils.degToRad(22.5)) * 1.04;
  const travel = view.zoom;
  camera.position.set(view.panX + view.x + focusPoint.x * travel, view.panY + view.y + focusPoint.y * travel, distance * (1 - travel * .56));
  camera.lookAt(view.panX + focusPoint.x * travel + view.x * .35, view.panY + focusPoint.y * travel + view.y * .35, 0);
  camera.updateMatrixWorld();
  renderer.render(scene, camera);
  for (const button of hotspots) {
    point.set((Number(button.dataset.x) - .5) * roomWidth, (.5 - Number(button.dataset.y)) * roomHeight, .02).project(camera);
    const x = (point.x + 1) * width / 2, y = (1 - point.y) * height / 2;
    button.style.left = `${x}px`;
    button.style.top = `${y}px`;
    button.hidden = x < 20 || x - 12 + hotspotWidths.get(button) > width - 20 || y < 100 || y > height - 160;
  }
  if (moving) frame = requestAnimationFrame(draw);
}
function render() { if (!frame && !document.hidden) { lastFrame = performance.now(); frame = requestAnimationFrame(draw); } }
function zoom(value) {
  target.zoom = Math.max(0, Math.min(1, value));
  if (target.zoom < .15) { target.panX = 0; target.panY = 0; }
  stage.classList.toggle("room-entered", target.zoom > .15);
  document.querySelector("#zoom-label").textContent = target.zoom < .15 ? "Room view" : target.zoom > .8 ? "At the desk" : "Getting closer";
  document.querySelector('[data-view="desk"]').setAttribute("aria-pressed", String(target.zoom > .15));
  if (!renderer) {
    document.querySelector(".room-poster").style.transform = `scale(${1 + target.zoom * .8})`;
    hotspots.forEach(button => { button.style.left = `${Number(button.dataset.x) * 100}%`; button.style.top = `${Number(button.dataset.y) * 100}%`; });
  }
  render();
}
async function createRoom() {
  try {
    renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: false, powerPreference: "low-power" });
    renderer.setPixelRatio(1); // The room is a single photograph; supersampling it adds GPU work without adding image detail.
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    scene = new THREE.Scene();
    camera = new THREE.PerspectiveCamera(45, 1, .1, 100);
    const texture = await new THREE.TextureLoader().loadAsync(new URL("./assets/ethan-sausage-legs.webp?v=__SITE_VERSION__", import.meta.url).href);
    texture.colorSpace = THREE.SRGBColorSpace;
    photo = new THREE.Mesh(new THREE.PlaneGeometry(roomWidth, roomHeight), new THREE.MeshBasicMaterial({ map: texture }));
    scene.add(photo); // A restrained camera over the original photo gives depth without distorting Ethan's face or inventing unseen parts of the room.
    new ResizeObserver(() => {
      width = stage.clientWidth; height = stage.clientHeight;
      hotspots.forEach(button => hotspotWidths.set(button, button.offsetWidth)); // Measure labels once per resize, not between style writes on every animation frame.
      camera.aspect = width / height; camera.updateProjectionMatrix();
      renderer.setSize(width, height, false); render();
    }).observe(stage);
    stage.classList.add("room-ready");
    document.querySelector(".room-loading").hidden = true;
  } catch (error) {
    if (renderer) { renderer.dispose(); renderer = null; }
    canvas.hidden = true;
    document.querySelector(".room-loading").textContent = "Photo view · use the buttons to explore";
    console.warn("The room uses its photograph when WebGL is unavailable.", error);
  }
}
void createRoom();
canvas.addEventListener("webglcontextlost", event => {
  event.preventDefault(); cancelAnimationFrame(frame); frame = 0;
  stage.classList.remove("room-ready");
});
canvas.addEventListener("webglcontextrestored", () => { stage.classList.add("room-ready"); render(); });
document.addEventListener("visibilitychange", () => { cancelAnimationFrame(frame); frame = 0; if (!document.hidden) render(); });
reduced.addEventListener("change", render);
stage.addEventListener("wheel", event => {
  if (event.ctrlKey || event.target.closest(".room-dock")) return;
  event.preventDefault();
  const delta = event.deltaY * (event.deltaMode === 1 ? 16 : event.deltaMode === 2 ? height : 1);
  zoom(target.zoom + Math.max(-.18, Math.min(.18, delta * .001)));
}, { passive: false });
let drag;
canvas.addEventListener("pointerdown", event => {
  if (event.button !== 0 || !camera || detail.open) return;
  const visibleHeight = 2 * camera.position.z * Math.tan(THREE.MathUtils.degToRad(22.5)); // Convert pointer movement into the photo's current camera scale so it follows the drag at every zoom level.
  drag = { id: event.pointerId, x: event.clientX, y: event.clientY, panX: target.panX, panY: target.panY, scale: visibleHeight / height, limitX: Math.max(.4, (roomWidth - visibleHeight * camera.aspect) / 2), limitY: Math.max(.3, (roomHeight - visibleHeight) / 2) };
  canvas.setPointerCapture(event.pointerId);
  canvas.classList.add("is-dragging");
});
canvas.addEventListener("pointermove", event => {
  if (drag?.id === event.pointerId) {
    target.panX = THREE.MathUtils.clamp(drag.panX - (event.clientX - drag.x) * drag.scale, -drag.limitX, drag.limitX);
    target.panY = THREE.MathUtils.clamp(drag.panY + (event.clientY - drag.y) * drag.scale, -drag.limitY, drag.limitY);
    view.panX = target.panX; view.panY = target.panY; // Dragging tracks the hand directly; easing here made the scene feel detached and laggy.
    view.x = target.x = 0; view.y = target.y = 0;
    render();
    return;
  }
  if (event.pointerType === "touch" || reduced.matches || detail.open) return;
  pointer = { x: (event.clientX / width - .5) * .28, y: -(event.clientY / height - .5) * .18 };
  target.x = pointer.x; target.y = pointer.y; render();
});
/** Release the room drag after pointer release, cancellation or lost capture. */
function endDrag(event) {
  if (drag?.id !== event.pointerId) return;
  drag = null;
  canvas.classList.remove("is-dragging");
  if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
}
for (const type of ["pointerup", "pointercancel", "lostpointercapture"]) canvas.addEventListener(type, endDrag);
canvas.addEventListener("pointerleave", () => { if (!drag) { target.x = 0; target.y = 0; render(); } });
canvas.addEventListener("keydown", event => {
  if (!["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Home", "Enter"].includes(event.key)) return;
  event.preventDefault();
  if (event.key === "ArrowUp" || event.key === "Enter") zoom(target.zoom + .2);
  if (event.key === "ArrowDown") zoom(target.zoom - .2);
  if (event.key === "Home") zoom(0);
  if (event.key === "ArrowLeft" || event.key === "ArrowRight") { target.panX = Math.max(-4, Math.min(4, target.panX + (event.key === "ArrowLeft" ? -.3 : .3))); render(); }
});
document.querySelector("#enter-room").addEventListener("click", () => { zoom(.85); document.querySelector('[data-view="desk"]').focus({ preventScroll: true }); });
document.querySelector("#zoom-in").addEventListener("click", () => zoom(target.zoom + .2));
document.querySelector("#zoom-out").addEventListener("click", () => zoom(target.zoom - .2));
document.querySelectorAll("[data-view]").forEach(button => button.addEventListener("click", () => {
  focusPoint = { x: -.7, y: .2 }; zoom(button.dataset.view === "room" ? 0 : .85);
  if (button.dataset.view === "room") document.querySelector("#enter-room").focus({ preventScroll: true });
}));

const topics = {
  corsair: ["Right hand · Agentic Mouse", "Corsair Scimitar", "Twelve thumb controls for working with agents, with the top button for VoiceInk++ dictation."],
  razer: ["Left hand · Agentic Mouse", "Razer Naga", "The same controls mirrored for my left hand, so I can switch whenever I want."],
  code: ["Great for Agentic Engineers", "Review code without moving your hand", "Quick press to jump to a change, or hold and release to stage the current file and jump in that direction."],
  voice: ["VoiceInk++", "YouTube pauses when I start talking", "I use a top mouse button to dictate instead of typing, and my video resumes when I finish if my setup paused it."],
  desk: ["My desk setup", "Both mice stay on the desk", "High sensitivity keeps movement small, and I sometimes use both mice to click through code review faster."],
  chair: ["My desk setup", "Lean back without reaching for a keyboard", "I use thumb controls and dictation with the footrest out, switching hands whenever I want."],
};
let returnFocus, returnView;
function openTopic(topic, trigger) {
  const copy = topics[topic];
  if (!copy) return;
  if (!detail.open) { returnFocus = trigger; returnView = { ...target }; }
  const anchor = hotspots.find(button => button.dataset.topic === (topic === "desk" ? "corsair" : topic));
  const zoomLevel = 1.25;
  target.zoom = zoomLevel;
  target.panX = (Number(anchor.dataset.x) - .5) * roomWidth - focusPoint.x * zoomLevel;
  target.panY = (.5 - Number(anchor.dataset.y)) * roomHeight - focusPoint.y * zoomLevel;
  target.x = 0; target.y = 0;
  stage.classList.add("room-focused");
  detail.dataset.topic = topic;
  render();
  document.querySelector("#detail-kicker").textContent = copy[0];
  document.querySelector("#detail-title").textContent = copy[1];
  document.querySelector("#detail-description").textContent = copy[2];
  const mouse = topic === "razer" || topic === "corsair";
  for (const name of ["mouse", "code", "voice", "setup"]) document.querySelector(`#${name}-detail`).hidden = name !== (mouse ? "mouse" : topic === "desk" || topic === "chair" ? "setup" : topic);
  if (mouse) {
    if (simulator) { simulator.chooseHand(topic); updateMouse(); }
    document.querySelectorAll(".beta-mice figure").forEach(figure => { figure.hidden = figure.dataset.mouse !== topic; });
    loadMouse(topic);
  }
  if (topic === "code") updateReview();
  if (topic === "voice") updateVoice();
  if (topic === "desk" || topic === "chair") showSetup(topic);
  if (!detail.open) detail.showModal();
  detail.scrollTop = 0;
  document.querySelector(".detail-close").focus({ preventScroll: true });
}
document.querySelectorAll("[data-topic]").forEach(button => button.addEventListener("click", () => openTopic(button.dataset.topic, button)));
document.querySelectorAll("[data-voice]").forEach(button => button.addEventListener("click", () => openTopic("voice", button)));
document.querySelector(".detail-close").addEventListener("click", () => detail.close());
detail.addEventListener("close", () => {
  Object.assign(target, returnView); // Closing a feature returns to the exact zoom and pan from which it was opened.
  stage.classList.remove("room-focused");
  render();
  document.querySelector(".video-example").classList.remove("is-playing");
  videoPlaying = videoOwned || videoPlaying; // Leaving dictation cancels it and resumes only the example video it paused.
  recording = false; videoOwned = false;
  reviewPress = null; clearTimeout(reviewTimer); // Escape can close the panel while a review key is still held; that cancelled hold must not stage on release.
  document.querySelectorAll("[data-review]").forEach(button => button.classList.remove("is-ready"));
  returnFocus?.focus({ preventScroll: true });
});

let simulator, updateHUD, pendingKeypad;
const loadedMice = new Set();
const mapRequest = fetch(new URL("./simulator-data.json?v=__SITE_VERSION__", import.meta.url)).then(response => {
  if (!response.ok) throw new Error(`Mouse map could not load (${response.status})`);
  return response.json();
}).then(map => {
  simulator = new MouseSimulator(map);
  for (const app of map.apps) {
    const option = document.createElement("option"); option.value = app.id; option.textContent = app.title; document.querySelector("#beta-app").append(option);
  }
  document.querySelector("#beta-app").value = simulator.app;
  updateHUD = createNativeHUD(document.querySelector("#beta-hud"), simulator, {
    activate: cell => { simulator.press(cell); updateMouse(); },
    preview: cell => { simulator.state.selected = cell; document.querySelector("#beta-feedback").textContent = simulator.control(cell).title; updateGestures(); },
    bindHold: () => {}, // Hold and wheel buttons provide explicit gestures in the beta, including touch and keyboard input.
    keydown: () => {},
  });
  updateMouse();
  document.querySelector("#mouse-detail").inert = false;
  return map;
}).catch(error => { document.querySelector("#beta-feedback").textContent = "The mouse map could not load. Reload to try again."; throw error; });
async function loadMouse(hand) {
  if (loadedMice.has(hand)) return;
  loadedMice.add(hand);
  try {
    const map = await mapRequest;
    await createHeroMouse(document.querySelector(`.beta-mice [data-mouse="${hand}"]`), map.sources[hand], (source, cell) => {
      simulator.chooseHand(source); simulator.press(cell); updateMouse();
    }, (_source, cell) => simulator.control(cell).title);
  } catch { loadedMice.delete(hand); }
}
function updateGestures() {
  const control = simulator.control(simulator.state.selected);
  document.querySelector("#beta-hold").disabled = !control.wheel && !control.keypad;
  for (const id of ["beta-wheel-up", "beta-wheel-down"]) document.getElementById(id).disabled = simulator.state.held === null;
}
function updateMouse() {
  updateHUD?.(); updateGestures();
  document.querySelector("#beta-feedback").textContent = simulator.state.text || simulator.state.output;
  clearTimeout(pendingKeypad);
  if (simulator.state.pending) pendingKeypad = setTimeout(() => { simulator.tick(performance.now()); updateMouse(); }, 850);
}
document.querySelector("#beta-app").addEventListener("change", event => { if (simulator) { simulator.chooseApp(event.target.value); updateMouse(); } });
document.querySelector("#beta-hold").addEventListener("click", () => { simulator.hold(simulator.state.selected); updateMouse(); });
document.querySelector("#beta-wheel-up").addEventListener("click", () => { simulator.wheel("up"); updateMouse(); });
document.querySelector("#beta-wheel-down").addEventListener("click", () => { simulator.wheel("down"); updateMouse(); });
document.querySelector("#beta-reset").addEventListener("click", () => { simulator.reset(); updateMouse(); });

const reviewFiles = [
  ["settings.json", '  {\n−   "reviewOnSave": false,\n+   "reviewOnSave": true,\n    "theme": "dark"\n  }'],
  ["review.ts", '  function nextChange() {\n−   openFile(next);\n+   openDiff(next);\n  }'],
  ["README.md", '  ## Review code\n+ Quick press to jump.\n+ Hold and release to stage and jump.'],
];
let reviewIndex = 0, reviewTimer, reviewPress;
const staged = new Set();
function updateReview() {
  document.querySelector("#code-file").textContent = `${reviewFiles[reviewIndex][0]}${staged.has(reviewIndex) ? " · staged" : ""}`;
  document.querySelector("#code-lines").textContent = reviewFiles[reviewIndex][1];
  document.querySelector("#code-staged").textContent = `${staged.size} staged`;
}
function reviewStep(direction, stageFile) {
  const previous = reviewIndex;
  if (stageFile) staged.add(previous);
  reviewIndex = (reviewIndex + direction + reviewFiles.length) % reviewFiles.length;
  document.querySelector("#review-feedback").textContent = `${stageFile ? `Staged ${reviewFiles[previous][0]} and opened` : "Opened"} ${reviewFiles[reviewIndex][0]}.`;
  updateReview();
}
for (const button of document.querySelectorAll("[data-review]")) {
  const begin = () => { reviewPress = { button, at: performance.now() }; clearTimeout(reviewTimer); reviewTimer = setTimeout(() => button.classList.add("is-ready"), 300); };
  const end = () => {
    if (reviewPress?.button !== button) return;
    reviewStep(Number(button.dataset.review), performance.now() - reviewPress.at >= 300);
    reviewPress = null; clearTimeout(reviewTimer); button.classList.remove("is-ready");
  };
  button.addEventListener("pointerdown", event => { if (event.button === 0) { begin(); button.setPointerCapture(event.pointerId); } });
  button.addEventListener("pointerup", end);
  button.addEventListener("pointercancel", () => { reviewPress = null; clearTimeout(reviewTimer); button.classList.remove("is-ready"); });
  button.addEventListener("keydown", event => { if ([" ", "Enter"].includes(event.key) && !event.repeat) { event.preventDefault(); begin(); } });
  button.addEventListener("keyup", event => { if ([" ", "Enter"].includes(event.key)) { event.preventDefault(); end(); } });
  button.addEventListener("click", event => { if (event.detail === 0) reviewStep(Number(button.dataset.review), false); }); // Key handlers prevent their default click; assistive activation can still dispatch a click without duration events.
}
document.querySelector("#review-reset").addEventListener("click", () => { staged.clear(); reviewIndex = 0; updateReview(); document.querySelector("#review-feedback").textContent = "Quick press to jump, or hold for 300 ms and release to stage the file and jump."; });

let videoPlaying = true, recording = false, videoOwned = false;
function updateVoice() {
  document.querySelector(".video-example").classList.toggle("is-playing", videoPlaying);
  document.querySelector("#video-toggle").textContent = videoPlaying ? "Pause video" : "Play video";
  document.querySelector("#video-status").textContent = videoPlaying ? "Playing" : recording && videoOwned ? "Paused for dictation" : "Paused";
  document.querySelector(".video-screen > span").textContent = videoPlaying ? "▶" : "Ⅱ";
  document.querySelector("#dictate").textContent = recording ? "Finish dictation" : "Start dictation";
  document.querySelector("#dictate").setAttribute("aria-pressed", String(recording));
}
document.querySelector("#video-toggle").addEventListener("click", () => { videoPlaying = !videoPlaying; updateVoice(); });
document.querySelector("#dictate").addEventListener("click", () => {
  recording = !recording;
  if (recording) {
    videoOwned = videoPlaying;
    videoPlaying = false;
    document.querySelector("#transcript").textContent = '“Review these changes and explain anything I need to check.”';
  } else {
    videoPlaying = videoOwned || videoPlaying;
    document.querySelector("#transcript").textContent = videoOwned ? "Transcript sent to my agent and the video resumes." : "Transcript sent to my agent; the video stays paused because it was already paused.";
    videoOwned = false;
  }
  updateVoice();
});
function showSetup(topic) {
  document.querySelector("#setup-detail").innerHTML = topic === "chair"
    ? '<img class="setup-detail-photo" src="./assets/ethan-lounging.webp?v=__SITE_VERSION__" width="1672" height="941" alt="Ethan reclining with the chair footrest extended" /><dl class="setup-detail-list"><dt>Chair</dt><dd>Hbada E3 Pro 2026 · grey</dd><dt>How I use it</dt><dd>Footrest out, mice on the desk and no extra pads attached to the chair.</dd></dl><a class="detail-link" href="./#setup">See the chair and purchase details ↗</a>'
    : '<img class="setup-detail-photo" src="./assets/ethan-lounging.webp?v=__SITE_VERSION__" width="1672" height="941" alt="The bamboo desk with both mice on its surface" /><dl class="setup-detail-list"><dt>Desk</dt><dd>FlexiSpot E7 Pro · 2025 model</dd><dt>Desktop</dt><dd>Bamboo · 180 × 80 cm</dd><dt>Frame</dt><dd>Black</dd><dt>Chair</dt><dd>Hbada E3 Pro 2026 · grey</dd><dt>Mouse DPI</dt><dd>2,750 on both mice</dd></dl><a class="detail-link" href="./#setup">See the hardware and purchase details ↗</a>';
}
