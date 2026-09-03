const SPARE = ["Spare", "No action is assigned to this cell in this mode."];

const CELLS = [
  { id: 1, corsair: 1, razer: 3 },
  { id: 2, corsair: 2, razer: 2 },
  { id: 3, corsair: 3, razer: 1 },
  { id: 4, corsair: 4, razer: 6 },
  { id: 5, corsair: 5, razer: 5 },
  { id: 6, corsair: 6, razer: 4 },
  { id: 7, corsair: 7, razer: 9 },
  { id: 8, corsair: 8, razer: 8 },
  { id: 9, corsair: 9, razer: 7 },
  { id: 10, corsair: 10, razer: 12 },
  { id: 11, corsair: 11, razer: 11 },
  { id: 12, corsair: 12, razer: 10 },
];

const LAYERS = {
  default: {
    label: "Default",
    actions: [
      ["Horizontal Scroll + Wheel", "Hold and ratchet: up scrolls right, down scrolls left."],
      ["Current app mode", "Open a live mode named and coloured for the frontmost app."],
      ["Screenshot / 2× Paste", "Save through native Shift-Command-4, copy the result, or rapid-double-press to paste it."],
      ["Copy / Paste + Wheel", "Hold and ratchet: up pastes, down copies."],
      ["Forward", "Go forward one page or navigation step."],
      ["YouTube Scrub + Wheel", "Click to rewind five seconds, or hold and ratchet to scrub by five seconds without focusing Chrome."],
      ["Enter", "Insert one native Return in the frontmost app."],
      ["Back", "Go back one page or navigation step."],
      ["Keys mode", "Open the shared native-key mode."],
      ["Legend toggle", "Show or hide this mouse's independent Default legend."],
      ["Switch App", "Hold to keep the macOS App Switcher open; release to choose."],
      ["Utility mode", "Open the shared Utility page immediately."],
    ],
  },
  vscodeBase: {
    label: "VS Code base",
    actions: [
      ["Horizontal Scroll + Wheel", "Inherited from Default."],
      ["Current app mode", "Open the VS Code child when VS Code is frontmost."],
      ["Screenshot / 2× Paste", "Inherited from Default."],
      ["Copy / Paste + Wheel", "Inherited from Default."],
      ["Previous Change", "Release sends Better Git Previous Change immediately, with no double-click wait."],
      ["YouTube Scrub + Wheel", "Inherited from Default."],
      ["Enter · 8 held: Stage + Next", "Press normally for Enter, or press while holding button 8 to stage and advance."],
      ["Next Change · Hold + Enter to Stage", "Release for Better Git Next Change, or hold while pressing the same mouse's Enter button to stage and advance."],
      ["Keys mode", "Inherited from Default."],
      ["Legend toggle", "Inherited from Default."],
      ["Switch App", "Inherited from Default."],
      ["Utility mode", "Inherited from Default."],
    ],
  },
  utility: {
    label: "Utility",
    actions: [
      ["Brightness + Wheel", "Hold and ratchet: up decreases, down increases."],
      ["Choose app", "Open the eleven-app manual selector."],
      ["Spaces + Wheel", "Hold; the first wheel-up moves right and wheel-down moves left, then release to re-arm."],
      ["Mission / Desktop + Wheel", "Hold and ratchet: up opens Mission Control, down shows the desktop."],
      ["App Exposé + Wheel", "Hold and ratchet down once for native App Exposé; wheel up is consumed."],
      ["Magnet + Wheel", "Hold and ratchet: up sends Magnet Left, down sends Magnet Right."],
      ["PP", "Private action."],
      ["Intelligence on demand", "Open Codex's global Option-Space window."],
      ["Keys mode", "Move directly into the shared Keys page."],
      ["Exit Utility mode", "Clear the mode lease and return to Default."],
      ["Zoom + Wheel", "Hold and ratchet: up zooms in, down zooms out."],
      ["Extra Utilities", "Open the nested page for manual layout restore and safe app quit."],
    ],
  },
  keys: {
    label: "Keys",
    actions: [
      ["Left Arrow", "Emit one native, non-repeating Left Arrow."],
      SPARE,
      ["Undo", "Emit Command-Z in the frontmost app."],
      ["Down Arrow", "Emit one native, non-repeating Down Arrow."],
      ["Up Arrow", "Emit one native, non-repeating Up Arrow."],
      ["Keypad", "Open classic phone-keypad text entry."],
      ["Right Arrow", "Emit one native, non-repeating Right Arrow."],
      ["Space", "Emit one native Space key."],
      ["Tracks + Wheel", "Click for Next Track, or hold and ratchet up for Next Track or down for Previous Track."],
      ["Exit Keys mode", "Clear the mode lease and return to Default."],
      ["Backspace", "Emit one native Delete/Backspace key."],
      SPARE,
    ],
    sourceOverrides: {
      razer: {
        1: ["Right Arrow", "Mirrored for the left-handed Razer's physical layout."],
        7: ["Left Arrow", "Mirrored for the left-handed Razer's physical layout."],
      },
    },
  },
  keypad: {
    label: "Keypad",
    actions: [
      ["Punctuation / Hold 1", "Cycle the visible punctuation set; hold for 1."],
      ["ABC / Hold 2", "Classic phone letters; hold for 2."],
      ["DEF / Hold 3", "Classic phone letters; hold for 3."],
      ["GHI / Hold 4", "Classic phone letters; hold for 4."],
      ["JKL / Hold 5", "Classic phone letters; hold for 5."],
      ["MNO / Hold 6", "Classic phone letters; hold for 6."],
      ["PQRS / Hold 7", "Classic phone letters; hold for 7."],
      ["TUV / Hold 8", "Classic phone letters; hold for 8."],
      ["WXYZ / Hold 9", "Classic phone letters; hold for 9."],
      ["Exit Keypad", "Leave Keypad and return to Default."],
      ["Space", "Insert a space."],
      ["Backspace / Hold Return", "Tap Backspace; hold to send Return."],
    ],
  },
  extra: {
    label: "Extra Utilities",
    actions: [
      ["Organize Windows", "Request one manual restore of the saved Stay layout."],
      SPARE, SPARE, SPARE, SPARE, SPARE, SPARE, SPARE,
      ["Quit App", "Send one ordinary Command-Q to the frontmost external app."],
      ["Exit Extra Utilities", "Return directly to Default."],
      SPARE, SPARE,
    ],
  },
  chooseApp: {
    label: "Choose app",
    actions: [
      ["Codex", "Lock the app-specific page to Codex without activating it."],
      ["Terminal", "Lock the app-specific page to Terminal."],
      ["Claude", "Lock the app-specific page to Claude."],
      ["Chrome", "Lock the app-specific page to Chrome."],
      ["iTerm", "Lock the app-specific page to iTerm."],
      ["Spotify", "Lock the app-specific page to Spotify."],
      ["VS Code", "Lock the app-specific page to VS Code."],
      ["Notion", "Lock the app-specific page to Notion."],
      ["OBS", "Lock the app-specific page to OBS."],
      ["Exit Choose app", "Return directly to Default."],
      ["Telegram", "Lock the app-specific page to Telegram."],
      ["Safari", "Lock the app-specific page to Safari."],
    ],
  },
  codex: {
    label: "Codex",
    actions: [
      ["Steer queued message", "Send Codex's built-in Command-Return shortcut; dispatch is not confirmation."],
      ["Exit Codex mode", "Return directly to Default."],
      ["Pin / unpin", "Send the configured Codex pin shortcut."],
      ["Reasoning Effort + Wheel", "Hold and ratchet: up increases effort, down decreases it."],
      ["New chat", "Send the configured Codex New Chat action."],
      ["Mute / unmute voice mic", "Toggle the mic only during an active Codex Voice Mode session."],
      ["Enter", "Emit one native Return."],
      ["Edit queued message ❌", "Known broken in the latest physical report; no successful action is claimed."],
      ["Open side chat", "Use Codex's Command-Option-S action while Codex is frontmost."],
      ["Exit Codex mode", "Return directly to Default."],
      ["Chats Selection + Wheel", "Hold and ratchet: up moves to the next chat, down to the previous chat."],
      ["Voice mode ❌", "Known broken in the latest physical report; the route remains under repair."],
    ],
  },
  claude: {
    label: "Claude",
    actions: [
      ["Settings", "Open Claude settings."],
      ["Exit Claude mode", "Return directly to Default."],
      ["Search", "Press Claude's exact Search control."],
      ["Voice mode", "Press Claude's exact Voice Mode control."],
      ["New chat", "Open a new Claude chat."],
      ["Mute / unmute voice mic", "Press Claude's exact microphone control."],
      ["Enter", "Emit one native Return to Claude."],
      ["Reload", "Reload Claude's current view."],
      ["Toggle sidebar", "Press Claude's exact sidebar control."],
      ["Exit Claude mode", "Return directly to Default."],
      ["Previous tab", "Move to Claude's previous tab."],
      ["Next tab", "Move to Claude's next tab."],
    ],
  },
  chrome: {
    label: "Chrome",
    actions: [
      ["Close current tab", "Send Command-W to the running Chrome process."],
      ["Exit Chrome mode", "Return directly to Default."],
      ["Open DevTools", "Send Chrome's Command-Option-I shortcut."],
      ["Tabs + Wheel", "Hold and ratchet: up moves to the previous tab, down to the next tab."],
      ["New tab", "Send Command-T to Chrome."],
      ["Reload current tab", "Send Command-R to Chrome."],
      ["Hold 2× speed", "Hold for 2× on the selected playing YouTube video; double-click locks/unlocks 2×."],
      ["New tab", "Send Command-T to Chrome."],
      ["Address / Search", "Focus Chrome's address/search field."],
      ["Exit Chrome mode", "Return directly to Default."],
      ["Reopen tab", "Reopen the most recently closed tab."],
      ["Find page", "Open Chrome's Find interface."],
    ],
  },
  vscodeMode: {
    label: "VS Code mode",
    actions: [
      ["Close tab", "Close the current editor tab."],
      ["Exit VS Code mode", "Return directly to Default."],
      ["Find", "Open VS Code's Find interface."],
      ["Toggle Terminal", "Toggle the integrated terminal."],
      ["Previous Change / Stage + Previous ×2", "Single goes previous; rapid double stages and goes previous."],
      ["Cursor History + Wheel", "Hold and ratchet: up goes forward, down goes back."],
      ["Command Palette", "Open the VS Code Command Palette."],
      ["Next Change / Stage + Next ×2", "Single goes next; rapid double stages and goes next."],
      ["Stage + Next / Undo Stage ×2", "Single stages and advances; rapid double undoes the exact last stage."],
      ["Exit VS Code mode", "Return directly to Default."],
      ["Go to Definition", "Send F12 to VS Code."],
      ["Interrupt terminal", "Send one app-targeted Control-C cycle."],
    ],
  },
  spotify: {
    label: "Spotify",
    actions: [
      ["Search", "Open Spotify Search."],
      ["Exit Spotify mode", "Return directly to Default."],
      ["Previous track", "Move to the previous track."],
      ["Next track", "Move to the next track."],
      ["Seek backward", "Seek backward in the current track."],
      ["Seek forward", "Seek forward in the current track."],
      ["Volume + Wheel", "Hold and ratchet: up raises Spotify volume, down lowers it."],
      SPARE,
      ["Shuffle", "Toggle Shuffle."],
      ["Exit Spotify mode", "Return directly to Default."],
      ["Repeat", "Toggle Repeat."],
      ["Queue", "Open the queue."],
    ],
  },
};

const DISPLAY_ORDER = {
  corsair: [3, 6, 9, 12, 2, 5, 8, 11, 1, 4, 7, 10],
  razer: [12, 9, 6, 3, 11, 8, 5, 2, 10, 7, 4, 1],
};

const state = { layer: "default", selected: 8, selectedDevice: "corsair", deviceView: "both" };
const byId = new Map(CELLS.map((cell) => [cell.id, cell]));
const elements = {
  corsairGrid: document.getElementById("corsair-grid"),
  razerGrid: document.getElementById("razer-grid"),
  deck: document.querySelector(".control-deck"),
  address: document.getElementById("bus-address"),
  action: document.getElementById("bus-action"),
  detail: document.getElementById("bus-detail"),
  layer: document.getElementById("bus-layer"),
  crosswalk: document.getElementById("bus-crosswalk"),
  deepLink: document.getElementById("bus-deep-link"),
};

function actionFor(cell, device = state.selectedDevice) {
  const layer = LAYERS[state.layer] || LAYERS.default;
  return layer.sourceOverrides?.[device]?.[cell.id] || layer.actions[cell.id - 1] || SPARE;
}

function renderGrid(device) {
  const grid = elements[`${device}Grid`];
  if (!grid) return;
  const fragment = document.createDocumentFragment();
  DISPLAY_ORDER[device].forEach((physicalCell) => {
    const cell = byId.get(physicalCell);
    const action = actionFor(cell, device);
    const button = document.createElement("button");
    button.type = "button";
    button.className = "mouse-cell";
    button.dataset.cell = String(cell.id);
    button.dataset.device = device;
    button.setAttribute("role", "radio");
    button.setAttribute("aria-checked", String(cell.id === state.selected));
    button.setAttribute(
      "aria-label",
      `${device === "corsair" ? "Corsair" : "Razer"} ${cell[device]}, physical cell ${cell.id}: ${action[0]}`,
    );
    if (cell.id === state.selected) button.classList.add("is-selected");
    button.innerHTML = `<b>${cell[device]}</b><span>${action[0]}</span>`;
    button.addEventListener("click", () => selectCell(cell.id, device));
    button.addEventListener("keydown", handleGridKeydown);
    fragment.append(button);
  });
  grid.replaceChildren(fragment);
}

function render() {
  if (!elements.deck) return;
  renderGrid("razer");
  renderGrid("corsair");
  const cell = byId.get(state.selected);
  const action = actionFor(cell, state.selectedDevice);
  elements.address.textContent = `PHYSICAL CELL ${cell.id}`;
  elements.action.textContent = action[0];
  elements.detail.textContent = action[1];
  elements.layer.textContent = (LAYERS[state.layer]?.label || state.layer).toUpperCase();
  elements.crosswalk.textContent = `C${cell.corsair} ↔ R${cell.razer}`;
  const baseLayer = state.layer === "default" || state.layer === "vscodeBase";
  elements.deepLink.href = baseLayer
    ? `./mouse-map.html${state.layer === "vscodeBase" ? "?layer=vscode" : ""}#c${cell.id}`
    : "https://github.com/EthanSK/agentic-mouse#what-the-included-helper-does";
  elements.deepLink.innerHTML = baseLayer
    ? "Open the transport map <span aria-hidden=\"true\">→</span>"
    : "Read the current-map notes <span aria-hidden=\"true\">↗</span>";
  elements.deck.dataset.deviceView = state.deviceView;
}

function selectCell(id, source) {
  state.selected = id;
  state.selectedDevice = source;
  render();
  document.querySelector(`.mouse-cell[data-device="${source}"][data-cell="${id}"]`)?.focus({ preventScroll: true });
}

function handleGridKeydown(event) {
  if (!["ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown"].includes(event.key)) return;
  event.preventDefault();
  const buttons = [...event.currentTarget.parentElement.querySelectorAll(".mouse-cell")];
  const current = buttons.indexOf(event.currentTarget);
  const delta = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -4, ArrowDown: 4 }[event.key];
  buttons[Math.max(0, Math.min(buttons.length - 1, current + delta))].focus();
}

document.querySelectorAll("[data-layer]").forEach((button) => {
  button.addEventListener("click", () => {
    state.layer = button.dataset.layer;
    document.querySelectorAll("[data-layer]").forEach((candidate) => {
      const active = candidate === button;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-checked", String(active));
    });
    render();
  });
});

document.querySelectorAll("[data-device-view]").forEach((button) => {
  button.addEventListener("click", () => {
    state.deviceView = button.dataset.deviceView;
    document.querySelectorAll("[data-device-view]").forEach((candidate) => {
      const active = candidate === button;
      candidate.classList.toggle("is-active", active);
      candidate.setAttribute("aria-checked", String(active));
    });
    render();
  });
});

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (event) => {
    const target = document.querySelector(link.getAttribute("href"));
    if (!target) return;
    event.preventDefault();
    target.scrollIntoView({ behavior: reducedMotion ? "auto" : "smooth", block: "start" });
  });
});

if (reducedMotion || !("IntersectionObserver" in window)) {
  document.querySelectorAll(".reveal").forEach((element) => element.classList.add("is-visible"));
} else {
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("is-visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.08 });
  document.querySelectorAll(".reveal").forEach((element) => observer.observe(element));
}

const clamp = (value, minimum = 0, maximum = 1) => Math.min(maximum, Math.max(minimum, value));
const lerp = (from, to, progress) => from + ((to - from) * progress);
const ease = (value) => 1 - ((1 - clamp(value)) ** 3);

function configureFutureStage() {
  const stage = document.getElementById("future");
  const sticky = stage?.querySelector(".future-sticky");
  const razer = stage?.querySelector(".future-mouse-razer");
  const corsair = stage?.querySelector(".future-mouse-corsair");
  const grid = stage?.querySelector(".stage-grid");
  const scenes = [...(stage?.querySelectorAll("[data-future-scene]") || [])];
  if (!stage || !sticky || !razer || !corsair || !scenes.length || reducedMotion) return;

  const centers = [0.04, 0.34, 0.64, 0.92];
  let pointerX = 0;
  let pointerY = 0;
  let requestedFrame = 0;

  function sceneOpacity(progress, center, index) {
    const width = index === 0 || index === centers.length - 1 ? 0.24 : 0.21;
    return clamp(1 - (Math.abs(progress - center) / width));
  }

  function update() {
    requestedFrame = 0;
    const rect = stage.getBoundingClientRect();
    const travel = Math.max(1, stage.offsetHeight - window.innerHeight);
    const progress = clamp(-rect.top / travel);
    const motion = ease(progress);
    sticky.style.setProperty("--future-progress", progress.toFixed(4));

    const inward = lerp(0, 7.4, motion);
    const rise = lerp(12, -1.5, motion);
    const razerScale = lerp(.76, .98, motion);
    const corsairScale = lerp(.72, .93, motion);
    razer.style.transform = `translate3d(${(-8 + inward + pointerX).toFixed(2)}vw, ${(rise + pointerY).toFixed(2)}vh, 0) rotateX(${lerp(19, 8, motion).toFixed(2)}deg) rotateY(${lerp(12, 3, motion).toFixed(2)}deg) rotateZ(${lerp(-16, -5, motion).toFixed(2)}deg) scale(${razerScale.toFixed(3)})`;
    corsair.style.transform = `translate3d(${(8 - inward + pointerX).toFixed(2)}vw, ${(rise - pointerY).toFixed(2)}vh, 0) rotateX(${lerp(17, 7, motion).toFixed(2)}deg) rotateY(${lerp(-12, -3, motion).toFixed(2)}deg) rotateZ(${lerp(16, 5, motion).toFixed(2)}deg) scale(${corsairScale.toFixed(3)})`;
    if (grid) grid.style.transform = `perspective(800px) rotateX(58deg) scale(1.7) translateY(${lerp(15, 4, motion).toFixed(2)}%)`;

    scenes.forEach((scene, index) => {
      const opacity = sceneOpacity(progress, centers[index], index);
      scene.style.opacity = opacity.toFixed(3);
      scene.style.transform = `translate3d(0, ${((1 - opacity) * 28).toFixed(1)}px, ${lerp(65, 110, opacity).toFixed(1)}px) scale(${lerp(.965, 1, opacity).toFixed(3)})`;
      scene.classList.toggle("is-visible", opacity > .36);
      scene.setAttribute("aria-hidden", String(opacity <= .36));
    });
  }

  function scheduleUpdate() {
    if (requestedFrame) return;
    requestedFrame = requestAnimationFrame(update);
  }

  sticky.addEventListener("pointermove", (event) => {
    pointerX = ((event.clientX / window.innerWidth) - .5) * .7;
    pointerY = ((event.clientY / window.innerHeight) - .5) * .45;
    scheduleUpdate();
  }, { passive: true });
  sticky.addEventListener("pointerleave", () => {
    pointerX = 0;
    pointerY = 0;
    scheduleUpdate();
  }, { passive: true });
  window.addEventListener("scroll", scheduleUpdate, { passive: true });
  window.addEventListener("resize", scheduleUpdate, { passive: true });
  update();
}

configureFutureStage();
render();
