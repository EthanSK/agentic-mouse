import { MouseSimulator } from "./simulator.mjs?v=__SITE_VERSION__";

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const sceneElement = document.querySelector("#button-scene");
const sceneControls = document.querySelector("#scene-controls");
const response = await fetch(
  document.querySelector('meta[name="mouse-map"]').content,
);
if (!response.ok)
  throw new Error(`Mouse map could not load (${response.status})`);
const map = await response.json();
const simulator = new MouseSimulator(map);
const CELLS = map.sources.corsair.modes.default.controls.map((control) => ({
  id: control.cell,
  corsair: control.printed,
  razer: map.sources.razer.modes.default.controls.find(
    (item) => item.cell === control.cell,
  ).printed,
}));
let hand = simulator.hand;
let selectedCell = simulator.state.selected;
let previewCell = selectedCell;
let updateScene = () => {};
let resetView = () => {};
let tourHasInput = false;
let suppressClick = false;
let pendingTimer;
let followHeroSelection = false;
let changeHand = (nextHand) => {
  simulator.chooseHand(nextHand);
  hand = nextHand;
  renderAll();
};
const sceneButtons = new Map();
const hudButtons = new Map();
const heldButtons = new WeakSet();

function rowsFor(source) {
  return map.sources[source].rows;
}

/** Use descriptions of the exported action rather than maintaining a second button map. */
function describe(control) {
  if (control.next === "default")
    return "Exit this mode and restore the Default controls.";
  if (control.next)
    return `Open ${map.sources[hand].modes[control.next].title}. The buttons and lighting change with it.`;
  if (control.keypad) {
    if (control.keypad.cycle.length)
      return `Tap to cycle ${control.keypad.cycle.join(" ")}. Hold for ${control.keypad.digit}.`;
    return control.keypad.hold
      ? "Tap for Backspace. Hold for Return."
      : `${control.title}. Type in the example below.`;
  }
  if (control.wheel)
    return `Hold this button. Wheel up: ${control.wheel.up ?? "no action"}. Wheel down: ${control.wheel.down ?? "no action"}.`;
  if (control.effect === "toggleLegend")
    return "Show or hide this mouse’s Default legend. Each mouse remembers its own choice.";
  if (control.title === "Spare") return "No action here";
  if (simulator.state.mode === "websites")
    return `Open ${control.title} in Chrome.`;
  const target = map.apps.find((app) => app.id === simulator.state.mode)?.title;
  return `${control.title}${target ? ` in ${target}` : ""}.${control.doublePress ? " Double press for the secondary action." : ""}${control.reportedBroken ? " Ethan reported this button as not working. The marker comes from the app source." : ""}`;
}

function previewControl(cell) {
  previewCell = cell;
  const physical = CELLS[cell - 1];
  const control = simulator.control(cell);
  document.querySelector("#control-address").textContent =
    `Corsair ${physical.corsair} · Razer ${physical.razer}`;
  document.querySelector("#control-title").textContent = control.title;
  document.querySelector("#control-detail").textContent = describe(control);
  updateScene();
}

/** Keep focused nodes in place while their actions and mode change. */
function renderControls() {
  let position = 0;
  selectedCell = simulator.state.selected;
  for (const cell of rowsFor(hand).flat()) {
    const button = sceneButtons.get(cell);
    const control = simulator.control(cell);
    button.textContent = control.printed;
    button.setAttribute(
      "aria-label",
      `${hand === "razer" ? "Razer" : "Corsair"} ${control.printed}: ${control.title}`,
    );
    button.setAttribute("aria-pressed", String(cell === selectedCell));
    if (sceneControls.children[position] !== button)
      sceneControls.insertBefore(
        button,
        sceneControls.children[position] ?? null,
      ); // Re-inserting a focused node on every action would lose keyboard focus.
    position += 1;
  }
  document
    .querySelectorAll("[data-hand], [data-hud-hand]")
    .forEach((button) => {
      button.setAttribute(
        "aria-pressed",
        String((button.dataset.hand ?? button.dataset.hudHand) === hand),
      );
    });
  document.querySelector("#scene-hand").textContent =
    hand === "razer" ? "Razer Naga" : "Corsair Scimitar";
  document.querySelector(".scene-origin img").src =
    hand === "razer" ? "./assets/razer-side.webp" : "./assets/corsair.webp";
  document.querySelector("#scene-mode").textContent = simulator.mode.title;
  sceneElement.style.setProperty("--mode-light", simulator.mode.color);
  previewControl(selectedCell);
}

function activate(cell, button) {
  if (heldButtons.has(button)) {
    heldButtons.delete(button);
    return;
  }
  if (suppressClick) return;
  tourHasInput = true;
  simulator.press(cell);
  renderAll();
  clearTimeout(pendingTimer);
  if (simulator.state.pending)
    pendingTimer = setTimeout(() => {
      simulator.tick();
      renderOutputs();
    }, map.keypadTimeout + 10);
}

/** A real long press uses the native keypad hold threshold; the explicit Hold button also works with a keyboard. */
function bindKeypadHold(button, cell) {
  let timer;
  button.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    heldButtons.delete(button);
    const key = simulator.control(cell).keypad;
    if (!key?.digit && !key?.hold) return;
    const source = hand;
    const mode = simulator.state.mode;
    timer = setTimeout(() => {
      if (suppressClick || source !== hand || mode !== simulator.state.mode)
        return;
      heldButtons.add(button);
      simulator.hold(cell);
      renderAll();
    }, map.holdThreshold);
  });
  for (const event of ["pointerup", "pointercancel", "pointerleave"])
    button.addEventListener(event, () => clearTimeout(timer));
}

/** Match the physical order for arrows; Enter and Space retain native button activation. */
function gridKeydown(event, cell, buttons) {
  const steps = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -4, ArrowDown: 4 };
  if (!Object.hasOwn(steps, event.key)) return;
  event.preventDefault();
  const order = rowsFor(hand).flat();
  buttons
    .get(
      order[Math.max(0, Math.min(11, order.indexOf(cell) + steps[event.key]))],
    )
    .focus();
}
for (const physical of CELLS) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "scene-key";
  button.dataset.cell = physical.id;
  button.addEventListener("pointerenter", (event) => {
    if (event.pointerType !== "touch" && !suppressClick) {
      tourHasInput = true;
      previewControl(physical.id);
    }
  });
  button.addEventListener("pointerleave", () => {
    if (!suppressClick) previewControl(selectedCell);
  });
  button.addEventListener("focus", () => {
    tourHasInput = true;
    previewControl(physical.id);
  });
  button.addEventListener("blur", () => previewControl(selectedCell));
  button.addEventListener("click", () => activate(physical.id, button));
  bindKeypadHold(button, physical.id);
  button.addEventListener("keydown", (event) =>
    gridKeydown(event, physical.id, sceneButtons),
  );
  sceneButtons.set(physical.id, button);
  const hudButton = document.createElement("button");
  hudButton.type = "button";
  hudButton.className = "hud-cell";
  hudButton.addEventListener("click", () => activate(physical.id, hudButton));
  bindKeypadHold(hudButton, physical.id);
  hudButton.addEventListener("focus", () => {
    document.querySelector("#hud-explanation").textContent = describe(
      simulator.control(physical.id),
    );
  });
  hudButton.addEventListener("pointerenter", () => {
    document.querySelector("#hud-explanation").textContent = describe(
      simulator.control(physical.id),
    );
  });
  hudButton.addEventListener("keydown", (event) =>
    gridKeydown(event, physical.id, hudButtons),
  );
  hudButtons.set(physical.id, hudButton);
}
document.querySelectorAll("[data-hand], [data-hud-hand]").forEach((button) =>
  button.addEventListener("click", () => {
    tourHasInput = true;
    changeHand(button.dataset.hand ?? button.dataset.hudHand);
  }),
);

function renderHUD() {
  const grid = document.querySelector("#hud-grid");
  document
    .querySelector("#hud-frame")
    .style.setProperty("--hud-accent", simulator.mode.color);
  document
    .querySelector(".hud-section")
    .style.setProperty("--mode-light", simulator.mode.color);
  document.querySelector("#mode-light-label").textContent =
    `${simulator.mode.title} lighting`;
  document.querySelector("#hud-mode-name").textContent = simulator.mode.title;
  document.querySelectorAll("[data-hud-mode]").forEach((button) => {
    button.setAttribute(
      "aria-pressed",
      String(button.dataset.hudMode === simulator.state.mode),
    );
    button
      .querySelector(".mode-dot")
      .style.setProperty(
        "--mode-color",
        map.sources[hand].modes[button.dataset.hudMode].color,
      );
  });
  document.querySelector("#more-modes").value = [
    "default",
    "utility",
    "keys",
    "keypad",
    "codex",
  ].includes(simulator.state.mode)
    ? ""
    : simulator.state.mode;
  document.querySelector("#hud-explanation").textContent = describe(
    simulator.control(selectedCell),
  );
  grid.classList.toggle(
    "legend-hidden",
    simulator.state.mode === "default" && !simulator.state.legend,
  );
  document.querySelector("#legend-hidden-note").hidden =
    simulator.state.mode !== "default" || simulator.state.legend;
  let position = 0;
  for (const cell of rowsFor(hand).flat()) {
    const control = simulator.control(cell);
    const button = hudButtons.get(cell);
    button.className = `hud-cell${control.reportedBroken ? " is-broken" : ""}`;
    button.style.setProperty(
      "--cell-color",
      control.destinationColor ?? control.color,
    );
    button.classList.toggle(
      "is-destination",
      Boolean(control.destinationColor),
    );
    button.setAttribute("aria-pressed", String(cell === selectedCell));
    button.setAttribute(
      "aria-label",
      `${hand === "razer" ? "Razer" : "Corsair"} ${control.printed}: ${control.title}${control.reportedBroken ? ", reported physical issue" : ""}`,
    );
    const number = document.createElement("span");
    number.className = "hud-number";
    number.textContent = control.printed;
    const caption = document.createElement("span");
    caption.className = "hud-title";
    caption.textContent = control.title;
    button.replaceChildren(number, caption);
    if (control.reportedBroken) {
      const repair = document.createElement("span");
      repair.className = "repair-chip";
      repair.textContent = "× Needs repair";
      button.append(repair);
    }
    if (grid.children[position] !== button)
      grid.insertBefore(button, grid.children[position] ?? null);
    position += 1;
  }
}

function renderOutputs() {
  document.querySelectorAll("[data-sim-output]").forEach((output) => {
    output.textContent = simulator.state.output;
    output.classList.toggle("is-typing", Boolean(simulator.state.pending));
  });
  document.querySelectorAll("[data-sim-history]").forEach((output) => {
    output.textContent = simulator.state.history.slice(-4, -1).join("  →  ");
  });
  document.querySelectorAll("[data-current-app]").forEach((select) => {
    select.value = simulator.app;
  });
  document.querySelectorAll("[data-app-hint]").forEach((hint) => {
    const entry = simulator.mode.controls.find(
      (item) => item.next === simulator.app,
    );
    hint.textContent =
      simulator.state.mode === "default" && entry
        ? `Press ${entry.printed} to open ${entry.title}`
        : simulator.state.followsApp
          ? "Follows the current app"
          : map.apps.some((app) => app.id === simulator.state.mode)
            ? "Manually selected app"
            : "Current app for Default controls";
  });
  const control = simulator.control(selectedCell);
  document.querySelectorAll("[data-sim-action]").forEach((button) => {
    const action = button.dataset.simAction;
    if (action === "hold") {
      button.hidden =
        !control.wheel && !control.keypad?.digit && !control.keypad?.hold;
      button.textContent =
        simulator.state.held === selectedCell ? "Stop hold" : "Hold";
      button.setAttribute(
        "aria-pressed",
        String(simulator.state.held === selectedCell),
      );
    }
    if (action === "up" || action === "down") {
      button.disabled = simulator.state.held === null;
      button.hidden = !control.wheel && simulator.state.held === null;
    }
    if (action === "double") button.hidden = !control.doublePress;
  });
}
function renderAll() {
  renderControls();
  renderHUD();
  renderOutputs();
}

document.querySelectorAll("[data-hud-mode]").forEach((button) =>
  button.addEventListener("click", () => {
    tourHasInput = true;
    simulator.chooseMode(button.dataset.hudMode);
    renderAll();
  }),
);
for (const [mode, definition] of Object.entries(map.sources.corsair.modes)) {
  if (
    ["default", "utility", "keys", "keypad", "codex", "unsupported"].includes(
      mode,
    )
  )
    continue;
  const option = document.createElement("option");
  option.value = mode;
  option.textContent = definition.title;
  document.querySelector("#more-modes").append(option);
}
document.querySelector("#more-modes").addEventListener("change", (event) => {
  if (event.target.value) {
    tourHasInput = true;
    simulator.chooseMode(event.target.value);
    renderAll();
  }
});
document.querySelectorAll("[data-current-app]").forEach((select) => {
  for (const app of map.apps) {
    const option = document.createElement("option");
    option.value = app.id;
    option.textContent = app.title;
    select.append(option);
  }
  select.addEventListener("change", () => {
    tourHasInput = true;
    simulator.chooseApp(select.value);
    renderAll();
  });
});
document.querySelectorAll("[data-sim-action]").forEach((button) =>
  button.addEventListener("click", () => {
    tourHasInput = true;
    switch (button.dataset.simAction) {
      case "hold":
        simulator.state.held === selectedCell
          ? simulator.release()
          : simulator.hold(selectedCell);
        break;
      case "up":
        simulator.wheel("up");
        break;
      case "down":
        simulator.wheel("down");
        break;
      case "double":
        simulator.doublePress(selectedCell);
        break;
      case "reset":
        simulator.reset();
        resetView();
        break;
    }
    renderAll();
  }),
);
document
  .querySelector("#reset-view")
  .addEventListener("click", () => resetView());
document.querySelector("#show-legend").addEventListener("click", () => {
  simulator.state.legend = true;
  renderAll();
});
renderAll();
let controlsWereVisible = false;
new IntersectionObserver(([entry]) => {
  const visible = entry.isIntersecting && entry.intersectionRatio >= .001;
  if (visible && !controlsWereVisible) {
    if (!followHeroSelection) changeHand("corsair"); // Returning from another section starts on the right mouse; an explicit hero-key click still opens that mouse's own action.
    followHeroSelection = false;
  }
  controlsWereVisible = visible;
}, { rootMargin: `-${getComputedStyle(document.documentElement).scrollPaddingTop} 0px 0px`, threshold: .001 }).observe(document.querySelector("#buttons")); // Anchor navigation leaves the previous section inside scroll-padding; exclude that strip when detecting a return.

/** Show an explicit dictation example; this never opens a microphone or native app. */
for (const button of document.querySelectorAll("[data-speech]")) {
  button.addEventListener("click", () => {
    const dialog = document.querySelector("#speech-demo");
    document.querySelector("#speech-hand").textContent =
      button.dataset.speech === "razer"
        ? "Razer Naga · Top button"
        : "Corsair Scimitar · Top button";
    dialog.showModal();
    document.querySelector("#speech-example").textContent =
      "Build me something cool. I’m staying right here.";
  });
}
document
  .querySelector("#close-speech")
  .addEventListener("click", () =>
    document.querySelector("#speech-demo").close(),
  );

/** Build the full mouse; native-exported cells remain the only mapping source. */
async function createButtonScene() {
  const THREE = await import("three");
  const { createMouseModel, lightStudio } = await import("./mouse-model.mjs?v=__SITE_VERSION__");
  const renderer = new THREE.WebGLRenderer({ canvas: document.querySelector("#control-canvas"), alpha: true, antialias: true });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  renderer.setClearColor(0x101115, 0);
  const scene = new THREE.Scene();
  lightStudio(renderer, scene, 1.1); // Same studio as the hero; a touch more exposure keeps the charcoal shell readable on the near-black chapter ground.
  const camera = new THREE.PerspectiveCamera(36, 1, 0.1, 50);
  camera.position.set(0, 0, 11.4);
  const assembly = new THREE.Group();
  scene.add(assembly);
  const models = Object.fromEntries(await Promise.all(["corsair", "razer"].map(async (source) => [source, await createMouseModel(source, map.sources[source])])));
  for (const model of Object.values(models)) assembly.add(model.group);
  const pose = {
    progress: 0,
    dragX: 0,
    dragY: 0,
    dragProgress: null,
  };
  const point = new THREE.Vector3();
  const normal = new THREE.Vector3();
  const direction = new THREE.Vector3();
  const raycaster = new THREE.Raycaster();
  raycaster.firstHitOnly = true;
  const focusColor = new THREE.Color("#ffffff");
  const corners = [
    new THREE.Vector3(.10, -.18, -.20), new THREE.Vector3(.10, -.18, .20),
    new THREE.Vector3(.10, .18, -.20), new THREE.Vector3(.10, .18, .20),
  ];
  let width = 0;
  let height = 0;
  let visible = true;

  /** Render on scroll or input only; project HTML hit targets from the actual key faces. */
  let renderFrame = 0;
  function render() {
    if (!renderFrame) renderFrame = requestAnimationFrame(draw); // Scroll, resize and selection can request the same view in one frame; draw it once.
  }
  function draw() {
    renderFrame = 0;
    if (!visible || !width || !height) return;
    const progress =
      pose.dragProgress ?? (reducedMotion.matches ? 0.7 : pose.progress);
    const model = models[hand];
    const keys = model.keys;
    const focusedButton = document.activeElement?.matches(".scene-key:focus-visible") ? document.activeElement : null;
    for (const [source, object] of Object.entries(models)) object.group.visible = source === hand;
    assembly.rotation.set(
      .12 + progress * .14 + pose.dragX,
      -model.side * Math.PI / 2 + model.side * progress * .17 + pose.dragY,
      -.025,
    );
    assembly.position.y = .4;
    for (const [cell, key] of keys) {
      const control = simulator.control(cell);
      const highlighted = cell === previewCell || simulator.state.held === cell;
      key.material.color.copy(key.userData.color);
      if (highlighted) key.material.color.set(control.destinationColor ?? control.color);
      if (highlighted) key.material.color.multiplyScalar(.5);
      key.material.emissive.set(highlighted ? (control.destinationColor ?? control.color) : "#000000");
      if (sceneButtons.get(cell) === focusedButton) key.material.emissive.lerp(focusColor, .55); // A flat HTML focus square crossed angled key edges; show keyboard focus on the actual key surface instead. (Codex task: 01a06ee5-4aa0-7a61-a029-704e5c44a8f2)
      key.material.emissiveIntensity = .3; // The calmer studio lowers ambient light; a slightly stronger glow keeps the selected key's mode colour legible on the charcoal shell.
      key.position.copy(key.userData.rest);
      if (simulator.state.held === cell) key.position.x -= model.side * .035;
    }
    camera.updateMatrixWorld(); // The first focus could jump far outside the chapter when keys were projected before the camera's first render.
    assembly.updateMatrixWorld(true);
    for (const [cell, key] of keys) {
      point.set(model.side * .10, 0, 0).applyMatrix4(key.matrixWorld).project(camera);
      const button = sceneButtons.get(cell);
      normal.set(model.side, 0, 0).transformDirection(key.matrixWorld);
      direction
        .copy(camera.position)
        .sub(key.getWorldPosition(new THREE.Vector3()))
        .normalize();
      raycaster.setFromCamera(new THREE.Vector2(point.x, point.y), camera);
      const hit = normal.dot(direction) > .18 ? raycaster.intersectObjects(model.pickables, false)[0] : null;
      button.style.visibility = hit?.object.userData.cell === cell ? "visible" : "hidden"; // Facing the camera is insufficient on a full shell: the palm or wheel can occlude a key after rotation.
      button.style.left = `${(point.x * 0.5 + 0.5) * width}px`;
      button.style.top = `${(-point.y * 0.5 + 0.5) * height}px`;
      const projected = corners.map((corner) =>
        corner.clone().setX(model.side * .10).applyMatrix4(key.matrixWorld).project(camera),
      );
      button.style.width = `${Math.max(8, (Math.max(...projected.map((p) => p.x)) - Math.min(...projected.map((p) => p.x))) * width * 0.45)}px`;
      button.style.height = `${Math.max(8, (Math.max(...projected.map((p) => p.y)) - Math.min(...projected.map((p) => p.y))) * height * 0.45)}px`; // Fixed hit boxes overlapped adjacent keys after rotation; size targets from each real key face.
      button.style.opacity = Math.max(0, 1 - Math.abs(pose.handTurn));
    }
    renderer.render(scene, camera);
  }
  updateScene = render;
  sceneControls.addEventListener("click", (event) => {
    if (suppressClick || event.target.closest("button")) return;
    const rect = sceneControls.getBoundingClientRect();
    raycaster.setFromCamera(new THREE.Vector2((event.clientX - rect.left) / rect.width * 2 - 1, -(event.clientY - rect.top) / rect.height * 2 + 1), camera);
    const hit = raycaster.intersectObjects(models[hand].pickables, false)[0];
    if (hit?.object.userData.speech) document.querySelector(`.hero-product[data-mouse="${hand}"] .speech-callout`).click();
  });
  let drag;
  sceneControls.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || sceneElement.classList.contains("scene-fallback"))
      return;
    suppressClick = false;
    drag = {
      id: event.pointerId,
      x: event.clientX,
      y: event.clientY,
      startX: pose.dragX,
      startY: pose.dragY,
      touch: event.pointerType === "touch",
    };
  });
  sceneControls.addEventListener("pointermove", (event) => {
    if (!drag || drag.id !== event.pointerId) return;
    const x = event.clientX - drag.x;
    const y = event.clientY - drag.y;
    if (!suppressClick && Math.hypot(x, y) < 7) return;
    if (drag.touch && !suppressClick && Math.abs(y) > Math.abs(x)) {
      drag = null;
      return;
    } // A vertical touch gesture scrolls the page; only a horizontal swipe takes ownership of rotation.
    tourHasInput = true;
    suppressClick = true;
    sceneControls.setPointerCapture(event.pointerId);
    sceneElement.classList.add("is-dragging");
    pose.dragProgress ??= reducedMotion.matches ? 0.7 : pose.progress;
    pose.dragY = drag.startY + x * 0.009;
    pose.dragX = Math.max(
      -1.2,
      Math.min(1.2, drag.startX + (drag.touch ? 0 : y * 0.007)),
    );
    render();
  });
  function endDrag(event) {
    if (!drag || drag.id !== event.pointerId) return;
    drag = null;
    sceneElement.classList.remove("is-dragging");
    if (sceneControls.hasPointerCapture(event.pointerId))
      sceneControls.releasePointerCapture(event.pointerId);
    setTimeout(() => {
      suppressClick = false;
    }, 0); // Keep the release-generated click suppressed after a drag; the next independent press starts normally.
  }
  sceneControls.addEventListener("pointerup", endDrag);
  sceneControls.addEventListener("pointercancel", endDrag);
  resetView = () => {
    pose.dragX = 0;
    pose.dragY = 0;
    pose.dragProgress = 0;
    render();
  };
  sceneControls.addEventListener(
    "wheel",
    (event) => {
      if (simulator.state.held === null || event.ctrlKey) return;
      event.preventDefault();
      simulator.wheel(event.deltaY < 0 ? "up" : "down");
      renderOutputs();
    },
    { passive: false },
  );
  changeHand = (nextHand) => { // The half-second flip disabled the selector and felt delayed; switch immediately and reserve motion for scrolling and dragging.
    if (nextHand === hand) return;
    hand = nextHand;
    simulator.chooseHand(hand);
    pose.dragX = 0;
    pose.dragY = 0;
    pose.dragProgress = 0;
    renderAll();
  };
  const resize = new ResizeObserver((entries) => {
    width = entries[0].contentRect.width;
    height = entries[0].contentRect.height;
    camera.aspect = width / height;
    camera.position.z = camera.aspect < 1 ? 11.4 / camera.aspect : 11.4;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    render();
  });
  resize.observe(sceneControls.parentElement); // Mobile puts the output below the model; project keys within the canvas's own box, not the entire chapter.
  const observer = new IntersectionObserver(
    (entries) => {
      visible = entries[0].isIntersecting;
      if (visible) render();
    },
    { rootMargin: "100px" },
  );
  observer.observe(sceneElement);
  sceneElement.classList.remove("scene-fallback");
  sceneElement.classList.add("has-mouse-model");
  sceneElement.dataset.engine = `three.js r${THREE.REVISION}`;
  renderer.domElement.addEventListener("webglcontextlost", (event) => {
    event.preventDefault();
    sceneElement.classList.add("scene-fallback");
  });
  renderer.domElement.addEventListener("webglcontextrestored", () => {
    sceneElement.classList.remove("scene-fallback");
    render();
  });
  reducedMotion.addEventListener("change", render);
  return { pose, render };
}

/** Tie movement to native scrolling; small screens retain a short, ordinary document flow. */
function createScrollStory(scene) {
  if (!window.gsap || !window.ScrollTrigger) return;
  gsap.registerPlugin(ScrollTrigger);
  const media = gsap.matchMedia();
  media.add("(prefers-reduced-motion: no-preference)", () => {
    gsap.to(".hero-product.left", {
      y: -38,
      ease: "none",
      scrollTrigger: {
        trigger: ".hero",
        start: "top top",
        end: "bottom top",
        scrub: 0.6,
      },
    });
    gsap.to(".hero-product.right", {
      y: -38,
      ease: "none",
      scrollTrigger: {
        trigger: ".hero",
        start: "top top",
        end: "bottom top",
        scrub: 0.6,
      },
    });
    gsap.fromTo(
      ".lounge-photo",
      { clipPath: "inset(0 10% round 20px)" },
      {
        clipPath: "inset(0 0% round 0px)",
        ease: "none",
        scrollTrigger: {
          trigger: ".lounge-photo",
          start: "top 85%",
          end: "center center",
          scrub: 0.4,
        },
      },
    );
    gsap.fromTo(
      ".voice-bars i",
      { scaleY: 0.3 },
      {
        scaleY: 1,
        repeat: 5,
        yoyo: true,
        stagger: 0.09,
        duration: 0.6,
        ease: "sine.inOut",
        scrollTrigger: {
          trigger: ".voice-feature",
          start: "top 85%",
          once: true,
        },
      },
    );
    gsap.utils
      .toArray(
        ".section-heading, .lounge-quote, .hud-features article, .setup-item, .creator-end h2",
      )
      .forEach((element) => {
        gsap.from(element, {
          y: 25,
          autoAlpha: 0,
          duration: 0.8,
          ease: "power2.out",
          scrollTrigger: { trigger: element, start: "top 93%", once: true },
        });
      });
  });
  if (scene)
    media.add(
      "(min-width: 761px) and (min-height: 851px) and (prefers-reduced-motion: no-preference)",
      () => {
        const story = document.querySelector(".control-story");
        story.classList.add("is-scroll-scene");
        gsap.to(scene.pose, {
          progress: 1,
          ease: "none",
          onUpdate: () => {
            const cell =
              scene.pose.progress < 0.34
                ? 3
                : scene.pose.progress < 0.67
                  ? 6
                  : 12;
            if (!tourHasInput && previewCell !== cell) {
              simulator.state.selected = cell;
              renderAll();
            } else scene.render(); // The scroll tour yields permanently on pointer or keyboard input so it never replaces a visitor's selection.
          },
          scrollTrigger: {
            trigger: story,
            start: "top top",
            end: "bottom bottom",
            scrub: 0.45,
          },
        });
        gsap.to(".chapter-progress i", {
          width: "100%",
          ease: "none",
          scrollTrigger: {
            trigger: story,
            start: "top top",
            end: "bottom bottom",
            scrub: true,
          },
        });
        return () => {
          story.classList.remove("is-scroll-scene");
          scene.pose.progress = 0;
          scene.render();
        };
      },
    );
  document.fonts.ready.then(() => ScrollTrigger.refresh());
}

createButtonScene()
  .then(createScrollStory)
  .catch((error) => {
    console.warn(
      "The 3D preview is unavailable; the interactive button grid remains available.",
      error,
    );
    createScrollStory(null);
  });

import("./hero-mice.mjs?v=__SITE_VERSION__").then(({ createHeroMouse }) => {
  for (const figure of document.querySelectorAll(".hero-product")) {
    void createHeroMouse(figure, map.sources[figure.dataset.mouse], (source, cell) => {
      followHeroSelection = !controlsWereVisible;
      hand = source;
      simulator.chooseHand(hand);
      resetView();
      activate(cell, sceneButtons.get(cell));
      document.querySelector("#buttons").scrollIntoView({ behavior: reducedMotion.matches ? "instant" : "smooth" });
    }, (source, cell) => {
      const state = simulator.states[source];
      const mode = state.mode === "default" ? map.sources[source].defaults[simulator.app] : map.sources[source].modes[state.mode];
      const control = mode.controls.find((item) => item.cell === cell);
      return `${source === "razer" ? "Razer" : "Corsair"} ${control.printed}: ${control.title}`;
    });
  }
}).catch((error) => console.warn("The interactive hero could not load.", error));
