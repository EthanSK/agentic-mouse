const CELLS = [
  {
    id: 1, corsair: 1, razer: 3,
    default: ["Horizontal scroll left", "Scroll the current surface horizontally to the left."],
    vscode: ["Horizontal scroll left", "Inherited from the global Default layer."],
    keys: ["Left Arrow", "Emit one native, non-repeating Left Arrow."],
    utility: ["Brightness Down", "Lower the current display brightness."],
  },
  {
    id: 2, corsair: 2, razer: 2,
    default: ["Switch App", "Hold to keep the macOS App Switcher open; release to choose."],
    vscode: ["Switch App", "The same global hold-open App Switcher action."],
    keys: ["Paste password", "Read the local When-Unlocked Keychain item and type it without the clipboard."],
    utility: ["Brightness Up", "Raise the current display brightness."],
  },
  {
    id: 3, corsair: 3, razer: 1,
    default: ["Screenshot", "Start or cancel the native selected-area screenshot session."],
    vscode: ["Screenshot", "The same global selected-area screenshot action."],
    keys: ["Paste", "Send the standard Command-V shortcut."],
    utility: ["Space Left", "Move one macOS desktop Space to the left."],
  },
  {
    id: 4, corsair: 4, razer: 6,
    default: ["Horizontal scroll right", "Scroll the current surface horizontally to the right."],
    vscode: ["Horizontal scroll right", "Inherited from the global Default layer."],
    keys: ["Down Arrow", "Emit one native, non-repeating Down Arrow."],
    utility: ["Zoom Out", "Send the standard macOS Command-Minus zoom shortcut."],
  },
  {
    id: 5, corsair: 5, razer: 5,
    default: ["Forward", "Go forward one page or navigation step."],
    vscode: ["Previous Change", "Move to the previous Better Git change through F17."],
    keys: ["Up Arrow", "Emit one native, non-repeating Up Arrow."],
    utility: ["Zoom In", "Send the standard macOS Command-Plus zoom shortcut."],
  },
  {
    id: 6, corsair: 6, razer: 4,
    default: ["App shortcut", "Stay silent unless the frontmost app has an explicit wildcard action."],
    vscode: ["Stage + Next", "Stage the current Better Git change and advance through F18."],
    keys: ["Copy", "Send the standard Command-C shortcut."],
    utility: ["Space Right", "Move one macOS desktop Space to the right."],
  },
  {
    id: 7, corsair: 7, razer: 9,
    default: ["Enter", "Insert exactly one native Return in the frontmost app."],
    vscode: ["Enter", "Inherited from the global Default layer."],
    keys: ["Right Arrow", "Emit one native, non-repeating Right Arrow."],
    utility: ["Keypad", "Open classic phone-keypad text entry."],
  },
  {
    id: 8, corsair: 8, razer: 8,
    default: ["Back", "Go back one page or navigation step."],
    vscode: ["Next Change", "Move to the next Better Git change through F13."],
    keys: ["Space", "Emit one native Space key."],
    utility: ["YouTube −5 sec", "Rewind the selected YouTube target without focusing Chrome."],
  },
  {
    id: 9, corsair: 9, razer: 7,
    default: ["Keys mode", "Open the shared native-key mode."],
    vscode: ["Keys mode", "The same global Keys mode entry."],
    keys: ["Next Track", "Emit the native system Next Track media key."],
    utility: ["Keys mode", "Move directly into the shared Keys page."],
  },
  {
    id: 10, corsair: 10, razer: 12,
    default: ["Legend toggle", "Show or hide the source-aware Default legend."],
    vscode: ["Legend toggle", "Show or hide the source-aware Default legend."],
    keys: ["Exit Keys mode", "Clear the expiring mode lease and restore Default."],
    utility: ["Exit Utility modes", "Clear the expiring mode lease and restore Default."],
  },
  {
    id: 11, corsair: 11, razer: 11,
    default: ["Current app mode", "Open a live mode named and coloured for the frontmost app."],
    vscode: ["VS Code mode", "Open the live VS Code-specific mode."],
    keys: ["Backspace", "Emit one native Delete/Backspace key."],
    utility: ["Choose app", "Open the manual Codex, Chrome and VS Code selector."],
  },
  {
    id: 12, corsair: 12, razer: 10,
    default: ["Utility modes", "Open the shared system-utility menu."],
    vscode: ["Utility modes", "The same global Utility entry."],
    keys: ["Utility modes", "Return to the Utility page without ending the lease."],
    utility: ["Spare", "Available for another utility."],
  },
];

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
  if (state.layer === "keys" && device === "razer") {
    if (cell.id === 1) return ["Right Arrow", "Emit one native, non-repeating Right Arrow."];
    if (cell.id === 7) return ["Left Arrow", "Emit one native, non-repeating Left Arrow."];
  }
  return cell[state.layer] || cell.default;
}

function renderGrid(device) {
  const grid = elements[`${device}Grid`];
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
  renderGrid("razer");
  renderGrid("corsair");
  const cell = byId.get(state.selected);
  const action = actionFor(cell, state.selectedDevice);
  elements.address.textContent = `PHYSICAL CELL ${cell.id}`;
  elements.action.textContent = action[0];
  elements.detail.textContent = action[1];
  elements.layer.textContent = state.layer.toUpperCase();
  elements.crosswalk.textContent = `C${cell.corsair} ↔ R${cell.razer}`;
  elements.deepLink.href = `./mouse-map.html${state.layer === "vscode" ? "?layer=vscode" : ""}#c${cell.id}`;
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
  const columns = 4;
  const delta = {
    ArrowLeft: -1,
    ArrowRight: 1,
    ArrowUp: -columns,
    ArrowDown: columns,
  }[event.key];
  const next = Math.max(0, Math.min(buttons.length - 1, current + delta));
  buttons[next].focus();
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

document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (event) => {
    const target = document.querySelector(link.getAttribute("href"));
    if (!target) return;
    event.preventDefault();
    target.scrollIntoView({ behavior: "smooth", block: "start" });
  });
});

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
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

render();
