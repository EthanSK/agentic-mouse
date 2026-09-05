/* The existing public map owns the actions and the physical crosswalk. Keep this tour a view of that data. */
const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
const sceneElement = document.querySelector("#button-scene");
const sceneControls = document.querySelector("#scene-controls");
const corsairRows = [
  [3, 6, 9, 12],
  [2, 5, 8, 11],
  [1, 4, 7, 10],
];
let hand = "corsair";
let selectedCell = 4;
let previewCell = 4;
let hudMode = "default";
let hudHand = "corsair";
let updateScene = () => {};
let tourHasInput = false;
let changeHand = (nextHand) => {
  hand = nextHand;
  renderControls();
};
const sceneButtons = new Map();

/** Read the shared map, including the Razer's deliberately mirrored arrow actions. */
function actionFor(mode, cell, source) {
  return (
    LAYERS[mode].sourceOverrides?.[source]?.[cell] ??
    LAYERS[mode].actions[cell - 1]
  ); // Default cell 6 really includes a 350 ms 2× hold; NormalMapping and YouTubeScrubHoldController confirm it despite older project prose. (Codex task: 01a06ee5-4aa0-7a61-a029-704e5c44a8f2)
}

/** Put the physical cells in the same three-by-four arrangement as the native HUD. */
function rowsFor(source) {
  return corsairRows.map((row) =>
    source === "razer" ? [...row].reverse() : row,
  );
}

/** Describe the selected physical button without sending any command to the Mac. */
function previewControl(cell) {
  previewCell = cell;
  const physical = CELLS[cell - 1];
  const action = actionFor("default", cell, hand);
  document.querySelector("#control-address").textContent =
    `Corsair ${physical.corsair} · Razer ${physical.razer}`;
  document.querySelector("#control-title").textContent = action[0];
  document.querySelector("#control-detail").textContent = action[1];
  updateScene();
}

/** Keep both the accessible button order and the 3D projection in the chosen hand's order. */
function renderControls() {
  let position = 0;
  for (const cell of rowsFor(hand).flat()) {
    const button = sceneButtons.get(cell);
    const label = CELLS[cell - 1][hand];
    button.textContent = label;
    button.setAttribute(
      "aria-label",
      `${hand === "razer" ? "Razer" : "Corsair"} ${label}: ${actionFor("default", cell, hand)[0]}`,
    );
    button.setAttribute("aria-pressed", String(cell === selectedCell));
    if (sceneControls.children[position] !== button)
      sceneControls.insertBefore(
        button,
        sceneControls.children[position] ?? null,
      ); // Moving a focused button on selection would lose its keyboard focus.
    position += 1;
  }
  document
    .querySelectorAll("[data-hand]")
    .forEach((button) =>
      button.setAttribute("aria-pressed", String(button.dataset.hand === hand)),
    );
  document.querySelector("#scene-hand").textContent =
    hand === "razer" ? "Razer Naga" : "Corsair Scimitar";
  document.querySelector(".scene-origin img").src =
    hand === "razer" ? "./assets/razer-side.webp" : "./assets/corsair.webp";
  previewControl(selectedCell);
}

for (const physical of CELLS) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "scene-key";
  button.addEventListener("pointerenter", (event) => {
    if (event.pointerType !== "touch") {
      tourHasInput = true;
      previewControl(physical.id);
    }
  });
  button.addEventListener("pointerleave", () => previewControl(selectedCell));
  button.addEventListener("focus", () => {
    tourHasInput = true;
    previewControl(physical.id);
  });
  button.addEventListener("blur", () => previewControl(selectedCell));
  button.addEventListener("click", () => {
    selectedCell = physical.id;
    renderControls();
  });
  button.addEventListener("keydown", (event) => {
    const steps = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -4, ArrowDown: 4 };
    if (!Object.hasOwn(steps, event.key)) return;
    event.preventDefault();
    const order = rowsFor(hand).flat();
    const index = Math.max(
      0,
      Math.min(11, order.indexOf(physical.id) + steps[event.key]),
    );
    sceneButtons.get(order[index]).focus();
  });
  sceneButtons.set(physical.id, button);
}
document.querySelectorAll("[data-hand]").forEach((button) =>
  button.addEventListener("click", () => {
    tourHasInput = true;
    changeHand(button.dataset.hand);
  }),
);
renderControls();

const modeColours = {
  default: "#b9adc9",
  utility: "#ab65ef",
  keys: "#f29a5e",
  keypad: "#72bad5",
  codex: "#76b3ab",
};

/** Recreate the app's readable colour groups without pretending the preview is a live HUD. */
function cellColour(title) {
  if (title.includes("Exit")) return "#413343";
  if (
    title.includes("mode") ||
    title === "Keypad" ||
    title.includes("Utilities")
  )
    return "#574270";
  if (title.includes("Wheel")) return "#333a4f";
  if (title === "Spare") return "#24232a";
  return "#3e3847";
}

/** Render every control from the existing map so the walkthrough stays in sync with it. */
function renderHUD() {
  const grid = document.querySelector("#hud-grid");
  grid.replaceChildren();
  document
    .querySelector("#hud-frame")
    .style.setProperty("--hud-accent", modeColours[hudMode] ?? "#9d8bb9");
  document
    .querySelector(".hud-section")
    .style.setProperty("--mode-light", modeColours[hudMode] ?? "#9d8bb9");
  document.querySelector("#mode-light-label").textContent =
    `${LAYERS[hudMode].label} lighting`;
  document.querySelector("#hud-mode-name").textContent = LAYERS[
    hudMode
  ].label.endsWith("mode")
    ? LAYERS[hudMode].label
    : `${LAYERS[hudMode].label} mode`;
  document
    .querySelectorAll("[data-hud-mode]")
    .forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.hudMode === hudMode),
      ),
    );
  document
    .querySelectorAll("[data-hud-hand]")
    .forEach((button) =>
      button.setAttribute(
        "aria-pressed",
        String(button.dataset.hudHand === hudHand),
      ),
    );
  document.querySelector("#more-modes").value = Object.hasOwn(
    modeColours,
    hudMode,
  )
    ? ""
    : hudMode;
  document.querySelector("#hud-explanation").textContent =
    hudMode === "codex"
      ? "Two ways out: buttons 2 and 10 both exit Codex mode. Select any control to see what it does."
      : "Select a control to see what it does.";
  for (const cell of rowsFor(hudHand).flat()) {
    const action = actionFor(hudMode, cell, hudHand);
    const broken = action[0].includes("❌");
    const title = action[0].replace(" ❌", "");
    const button = document.createElement("button");
    button.type = "button";
    button.className = `hud-cell${broken ? " is-broken" : ""}`;
    button.style.setProperty("--cell-color", cellColour(title));
    button.setAttribute("aria-pressed", "false");
    button.setAttribute(
      "aria-label",
      `${hudHand === "razer" ? "Razer" : "Corsair"} ${CELLS[cell - 1][hudHand]}: ${title}${broken ? ", reported physical issue" : ""}`,
    );
    const number = document.createElement("span");
    number.className = "hud-number";
    number.textContent = CELLS[cell - 1][hudHand];
    const caption = document.createElement("span");
    caption.className = "hud-title";
    caption.textContent = title;
    button.append(number, caption);
    if (broken) {
      const repair = document.createElement("span");
      repair.className = "repair-chip";
      repair.textContent = "× Needs repair";
      button.append(repair);
    }
    button.addEventListener("click", () => {
      grid
        .querySelectorAll("button")
        .forEach((item) =>
          item.setAttribute("aria-pressed", String(item === button)),
        );
      document.querySelector("#hud-explanation").textContent =
        `${title}. ${action[1]}`;
    });
    grid.append(button);
  }
}
document.querySelectorAll("[data-hud-mode]").forEach((button) =>
  button.addEventListener("click", () => {
    hudMode = button.dataset.hudMode;
    renderHUD();
  }),
);
document.querySelectorAll("[data-hud-hand]").forEach((button) =>
  button.addEventListener("click", () => {
    hudHand = button.dataset.hudHand;
    renderHUD();
  }),
);
for (const [mode, layer] of Object.entries(LAYERS)) {
  if (Object.hasOwn(modeColours, mode)) continue;
  const option = document.createElement("option");
  option.value = mode;
  option.textContent = layer.label;
  document.querySelector("#more-modes").append(option);
}
document.querySelector("#more-modes").addEventListener("change", (event) => {
  if (event.target.value) {
    hudMode = event.target.value;
    renderHUD();
  }
});
renderHUD();

/** Load the GPU chapter after the HTML controls work; unsupported WebGL keeps the same usable grid. */
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
  const pose = { progress: 0, handTurn: 0 };
  const point = new THREE.Vector3();
  let width = 0;
  let height = 0;
  let visible = true;

  /** Render on scroll or input only; project HTML hit targets from the actual key faces. */
  function render() {
    if (!visible || !width || !height) return;
    const progress = reducedMotion.matches ? 0.7 : pose.progress;
    assembly.rotation.set(
      0.28 - progress * 0.33,
      (hand === "razer" ? 1 : -1) * (0.38 - progress * 0.29) + pose.handTurn,
      -0.11 + progress * 0.14,
    );
    assembly.position.y = 0.07;
    rowsFor(hand).forEach((row, rowIndex) =>
      row.forEach((cell, columnIndex) => {
        const key = keys.get(cell);
        key.position.set(
          (columnIndex - 1.5) * 1.17,
          (1 - rowIndex) * 1.14,
          0.48 + progress * 0.13 + (cell === previewCell ? 0.11 : 0),
        );
        key.material.color.setHex(cell === previewCell ? 0x503079 : 0x282534);
        key.material.emissive.setHex(
          cell === previewCell ? 0x221238 : 0x000000,
        );
      }),
    );
    camera.updateMatrixWorld(); // The first focus could jump far outside the chapter when keys were projected before the camera's first render.
    assembly.updateMatrixWorld(true);
    for (const [cell, key] of keys) {
      point.set(0, 0, 0.145).applyMatrix4(key.matrixWorld).project(camera);
      const button = sceneButtons.get(cell);
      button.style.left = `${(point.x * 0.5 + 0.5) * width}px`;
      button.style.top = `${(-point.y * 0.5 + 0.5) * height}px`;
      button.style.width = `${Math.min(width * 0.17, height * 0.15)}px`;
      button.style.height = `${height * 0.135}px`;
      button.style.opacity = Math.max(0, 1 - Math.abs(pose.handTurn));
    }
    renderer.render(scene, camera);
  }
  updateScene = render;
  changeHand = (nextHand) => {
    if (nextHand === hand) return;
    if (reducedMotion.matches || !window.gsap) {
      hand = nextHand;
      renderControls();
      return;
    }
    document.querySelectorAll("[data-hand]").forEach((button) => {
      button.disabled = true;
    });
    gsap.to(pose, {
      handTurn: Math.PI / 2,
      duration: 0.2,
      ease: "power2.in",
      onUpdate: render,
      onComplete: () => {
        hand = nextHand;
        pose.handTurn = -Math.PI / 2;
        renderControls();
        gsap.to(pose, {
          handTurn: 0,
          duration: 0.3,
          ease: "power2.out",
          onUpdate: render,
          onComplete: () => {
            document.querySelectorAll("[data-hand]").forEach((button) => {
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
      "(min-width: 761px) and (prefers-reduced-motion: no-preference)",
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
              selectedCell = cell;
              renderControls();
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
