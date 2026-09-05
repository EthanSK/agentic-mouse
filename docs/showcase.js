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

/** Build the draggable physical grid. */
async function createButtonScene() {
  const THREE = await import("three");
  const [{ RoundedBoxGeometry }, { RoomEnvironment }] = await Promise.all([
    import("./lib/RoundedBoxGeometry.js"),
    import("./lib/RoomEnvironment.js"),
  ]);
  const renderer = new THREE.WebGLRenderer({
    canvas: document.querySelector("#control-canvas"),
    alpha: true,
    antialias: true,
  });
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
  renderer.setClearColor(0x101115, 0);
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1.05;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFShadowMap;
  const scene = new THREE.Scene();
  const environment = new RoomEnvironment();
  const pmrem = new THREE.PMREMGenerator(renderer);
  const environmentMap = pmrem.fromScene(environment, 0.04);
  scene.environment = environmentMap.texture;
  environment.dispose();
  pmrem.dispose();
  const camera = new THREE.PerspectiveCamera(36, 1, 0.1, 40);
  camera.position.set(0, 0.1, 10.6);
  const assembly = new THREE.Group();
  assembly.scale.setScalar(0.83); // Leave a clear space below the model for action feedback, including rotated views.
  scene.add(assembly);
  const shell = new THREE.Mesh(
    new RoundedBoxGeometry(5.3, 3.95, 0.4, 5, 0.33),
    new THREE.MeshPhysicalMaterial({
      color: 0x303039,
      metalness: 0.6,
      roughness: 0.32,
      clearcoat: 0.25,
    }),
  );
  shell.castShadow = true;
  shell.receiveShadow = true;
  assembly.add(shell);
  const rim = new THREE.Mesh(
    new RoundedBoxGeometry(5.1, 3.75, 0.15, 4, 0.24),
    new THREE.MeshStandardMaterial({
      color: 0x14131b,
      metalness: 0.45,
      roughness: 0.42,
    }),
  );
  rim.position.z = 0.26;
  assembly.add(rim);
  const keyGeometry = new RoundedBoxGeometry(1.035, 0.99, 0.28, 4, 0.1);
  const keys = new Map();
  for (const physical of CELLS) {
    const key = new THREE.Mesh(
      keyGeometry,
      new THREE.MeshPhysicalMaterial({
        color: 0x32303b,
        metalness: 0.12,
        roughness: 0.55,
        clearcoat: 0.08,
        envMapIntensity: 0.25,
      }),
    );
    key.castShadow = true;
    key.receiveShadow = true;
    assembly.add(key);
    keys.set(physical.id, key);
  }
  const keyLight = new THREE.DirectionalLight(0xe4dcff, 1.8);
  keyLight.position.set(-3, 5, 7);
  keyLight.castShadow = true;
  keyLight.shadow.mapSize.set(1024, 1024);
  keyLight.shadow.camera.left = -7;
  keyLight.shadow.camera.right = 7;
  keyLight.shadow.camera.top = 7;
  keyLight.shadow.camera.bottom = -7;
  keyLight.shadow.normalBias = 0.04;
  scene.add(keyLight);
  const fillLight = new THREE.DirectionalLight(0xb298f5, 1.1);
  fillLight.position.set(5, -1, 3);
  scene.add(fillLight);
  const floor = new THREE.Mesh(
    new THREE.PlaneGeometry(30, 30),
    new THREE.ShadowMaterial({ opacity: 0.15 }),
  );
  floor.position.z = -1.5;
  floor.receiveShadow = true;
  scene.add(floor);
  const pose = {
    progress: 0,
    handTurn: 0,
    dragX: 0,
    dragY: 0,
    dragProgress: null,
  };
  const point = new THREE.Vector3();
  const normal = new THREE.Vector3();
  const direction = new THREE.Vector3();
  const corners = [
    new THREE.Vector3(-0.46, -0.43, 0.145),
    new THREE.Vector3(0.46, -0.43, 0.145),
    new THREE.Vector3(-0.46, 0.43, 0.145),
    new THREE.Vector3(0.46, 0.43, 0.145),
  ];
  let width = 0;
  let height = 0;
  let visible = true;

  /** Render on scroll or input only; project HTML hit targets from the actual key faces. */
  function render() {
    if (!visible || !width || !height) return;
    const progress =
      pose.dragProgress ?? (reducedMotion.matches ? 0.7 : pose.progress);
    assembly.rotation.set(
      0.28 - progress * 0.33 + pose.dragX,
      (hand === "razer" ? 1 : -1) * (0.38 - progress * 0.29) +
        pose.handTurn +
        pose.dragY,
      -0.11 + progress * 0.14,
    );
    assembly.position.y = 0.25;
    rowsFor(hand).forEach((row, rowIndex) =>
      row.forEach((cell, columnIndex) => {
        const key = keys.get(cell);
        key.position.set(
          (columnIndex - 1.5) * 1.17,
          (1 - rowIndex) * 1.14,
          0.48 + progress * 0.13 + (cell === previewCell ? 0.11 : 0),
        );
        const control = simulator.control(cell);
        const highlighted =
          cell === previewCell || simulator.state.held === cell;
        key.material.color.set(control.destinationColor ?? control.color);
        if (highlighted) key.material.color.multiplyScalar(0.65);
        else key.material.color.lerp(new THREE.Color("#222129"), 0.995); // A full rainbow hid the selected control; retain the native accent as a quiet tint until hover or hold. (Codex task: 01a06ee5-4aa0-7a61-a029-704e5c44a8f2)
        key.material.emissive.set(
          cell === previewCell || simulator.state.held === cell
            ? (control.destinationColor ?? control.color)
            : "#000000",
        );
        key.material.emissiveIntensity = 0.14;
      }),
    );
    camera.updateMatrixWorld(); // The first focus could jump far outside the chapter when keys were projected before the camera's first render.
    assembly.updateMatrixWorld(true);
    for (const [cell, key] of keys) {
      point.set(0, 0, 0.145).applyMatrix4(key.matrixWorld).project(camera);
      const button = sceneButtons.get(cell);
      normal.set(0, 0, 1).transformDirection(key.matrixWorld);
      direction
        .copy(camera.position)
        .sub(key.getWorldPosition(new THREE.Vector3()))
        .normalize();
      button.style.visibility =
        normal.dot(direction) > 0.18 ? "visible" : "hidden"; // A rotated back face must not leave invisible clickable buttons over the solid shell.
      button.style.left = `${(point.x * 0.5 + 0.5) * width}px`;
      button.style.top = `${(-point.y * 0.5 + 0.5) * height}px`;
      const projected = corners.map((corner) =>
        corner.clone().applyMatrix4(key.matrixWorld).project(camera),
      );
      button.style.width = `${Math.max(8, (Math.max(...projected.map((p) => p.x)) - Math.min(...projected.map((p) => p.x))) * width * 0.45)}px`;
      button.style.height = `${Math.max(8, (Math.max(...projected.map((p) => p.y)) - Math.min(...projected.map((p) => p.y))) * height * 0.45)}px`; // Fixed hit boxes overlapped adjacent keys after rotation; size targets from each real key face.
      button.style.opacity = Math.max(0, 1 - Math.abs(pose.handTurn));
    }
    renderer.render(scene, camera);
  }
  updateScene = render;
  let drag;
  let renderFrame = 0;
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
    if (!renderFrame)
      renderFrame = requestAnimationFrame(() => {
        renderFrame = 0;
        render();
      });
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
    pose.dragProgress = null;
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
  changeHand = (nextHand) => {
    if (nextHand === hand) return;
    if (reducedMotion.matches || !window.gsap) {
      hand = nextHand;
      simulator.chooseHand(hand);
      renderAll();
      return;
    }
    document
      .querySelectorAll("[data-hand], [data-hud-hand]")
      .forEach((button) => {
        button.disabled = true;
      });
    gsap.to(pose, {
      handTurn: Math.PI / 2,
      duration: 0.2,
      ease: "power2.in",
      onUpdate: render,
      onComplete: () => {
        hand = nextHand;
        simulator.chooseHand(hand);
        pose.dragX = 0;
        pose.dragY = 0;
        pose.handTurn = -Math.PI / 2;
        renderAll();
        gsap.to(pose, {
          handTurn: 0,
          duration: 0.3,
          ease: "power2.out",
          onUpdate: render,
          onComplete: () => {
            document
              .querySelectorAll("[data-hand], [data-hud-hand]")
              .forEach((button) => {
                button.disabled = false;
              });
          },
        });
      },
    });
  };
  const resize = new ResizeObserver((entries) => {
    width = entries[0].contentRect.width;
    height = entries[0].contentRect.height;
    camera.aspect = width / height;
    camera.position.z = camera.aspect < 1 ? 10.6 / camera.aspect : 10.6;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height, false);
    render();
  });
  resize.observe(sceneElement);
  const observer = new IntersectionObserver(
    (entries) => {
      visible = entries[0].isIntersecting;
      if (visible) render();
    },
    { rootMargin: "100px" },
  );
  observer.observe(sceneElement);
  sceneElement.classList.remove("scene-fallback");
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
    gsap.to(".hero-product.left img", {
      y: -58,
      x: -25,
      rotation: -6,
      ease: "none",
      scrollTrigger: {
        trigger: ".hero",
        start: "top top",
        end: "bottom top",
        scrub: 0.6,
      },
    });
    gsap.to(".hero-product.right img", {
      y: -58,
      x: 25,
      rotation: 6,
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
