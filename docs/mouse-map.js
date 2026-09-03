const SIGNALS = {
  pointing: {
    glyph: "●",
    name: "Native pointing button",
    description: "Behaves like an ordinary five-button mouse's Back/Forward event in normal apps.",
  },
  media: {
    glyph: "◎",
    name: "Native media key",
    description: "The system-level media key, so it reaches whichever app is playing.",
  },
  keyboard: {
    glyph: "□",
    name: "Keystroke",
    description: "A synthesized key press, because the target only listens for a shortcut.",
  },
  consumed: {
    glyph: "×",
    name: "Consumed transport",
    description: "Karabiner swallows the harmless raw key so it never reaches an app.",
  },
  runtime: {
    glyph: "◆",
    name: "Runtime-owned control",
    description: "Karabiner consumes the raw key; Agentic Mouse owns this control only while its explicit mode is active.",
  },
};

const PAIRS = [
  {
    id: "c1", corsair: 1, razer: 3, row: 3, col: 1,
    action: "Horizontal Scroll + Wheel", short: "Horizontal", description: "Hold the cell and ratchet the wheel: up moves right, down moves left.",
    signal: "runtime", output: "Agentic Mouse native horizontal-scroll chord", status: "IMPLEMENTED · PHYSICAL ACCEPTANCE PENDING",
  },
  {
    id: "c2", corsair: 2, razer: 2, row: 2, col: 1,
    action: "Current app mode", short: "App mode", description: "Open the mode for the current frontmost application and follow later app changes.",
    signal: "runtime", output: "Agentic Mouse current-app mode", status: "IMPLEMENTED · PHYSICAL ACCEPTANCE PENDING",
  },
  {
    id: "c3", corsair: 3, razer: 1, row: 1, col: 1,
    action: "Screenshot / 2× Paste", short: "Screenshot", description: "Save through the native selected-area crosshair, or rapid-double-press to paste the last saved screenshot.",
    signal: "runtime", output: "native Shift-Command-4 interaction", status: "PHYSICALLY REPORTED WORKING · EXACT SOURCE NOT RECORDED",
  },
  {
    id: "c4", corsair: 4, razer: 6, row: 3, col: 2,
    action: "Copy / Paste + Wheel", short: "Copy · Paste", description: "Hold and ratchet: up pastes, down copies.",
    signal: "runtime", output: "Agentic Mouse held-wheel chord", status: "IMPLEMENTED · PHYSICAL ACCEPTANCE PENDING",
  },
  {
    id: "c5", corsair: 5, razer: 5, row: 2, col: 2,
    action: "Forward", short: "Forward", description: "Go forward one page or step.",
    signal: "pointing", output: "pointing_button button5", status: "CONFIGURED · NATIVE POINTER OUTPUT",
    vscodeAction: {
      action: "Previous Change", short: "Previous", description: "Release sends one non-repeating F17 Previous Change with no double-click wait.",
      signal: "keyboard", output: "F17 on release · repeat false", status: "IMPLEMENTED · PHYSICAL ACCEPTANCE PENDING",
    },
  },
  {
    id: "c6", corsair: 6, razer: 4, row: 1, col: 2,
    action: "YouTube Scrub + Wheel", short: "YouTube scrub", description: "Click to rewind five seconds, or hold and ratchet to scrub by five seconds without focusing Chrome.",
    signal: "runtime", output: "VoiceInk bridge · click −5 · wheel ±5 seconds", status: "INSTALLED · PHYSICAL ACCEPTANCE PENDING",
  },
  {
    id: "c7", corsair: 7, razer: 9, row: 3, col: 3,
    action: "Enter", short: "Enter", description: "Insert exactly one newline in the frontmost application.",
    signal: "keyboard", output: "return_or_enter · repeat false", status: "CONFIGURED · EXACT-DEVICE OUTPUT",
    vscodeAction: {
      action: "Enter · Stage + Next after 8", short: "Enter · Stage", description: "Press normally for Enter, or emit F18 Stage + Next while the same mouse's cell 8 is held and for one second after it releases.",
      signal: "keyboard", output: "return_or_enter normally · F18 while cell 8 is held or for 1 sec after release", status: "IMPLEMENTED · PHYSICAL ACCEPTANCE PENDING",
    },
  },
  {
    id: "c8", corsair: 8, razer: 8, row: 2, col: 3,
    action: "Back", short: "Back", description: "Go back one page or step.",
    signal: "pointing", output: "pointing_button button4", status: "CONFIGURED · NATIVE POINTER OUTPUT",
    vscodeAction: {
      action: "Next · Enter stages for +1s", short: "Next · Stage", description: "Release sends F13 Next Change; the same mouse's Enter cell emits F18 Stage + Next while held and for one second after release.",
      signal: "keyboard", output: "F13 on release · same-source Enter emits F18 while held or for +1 sec", status: "IMPLEMENTED · PHYSICAL ACCEPTANCE PENDING",
    },
  },
  {
    id: "c9", corsair: 9, razer: 7, row: 1, col: 3,
    action: "Keys mode", short: "Keys", description: "Open the shared native keys mode; active cell 10 exits.",
    signal: "runtime", output: "Agentic Mouse Keys mode", status: "PHYSICALLY REPORTED WORKING · EXACT SOURCE MATRIX OPEN",
  },
  {
    id: "c10", corsair: 10, razer: 12, row: 3, col: 4,
    action: "Legend / Exit", short: "Legend · Exit", description: "Toggle this mouse's Default legend outside modes; exit the current mode while one is active.",
    signal: "runtime", output: "Default legend toggle / active-mode Exit", status: "PHYSICALLY ACCEPTED · INDEPENDENT PER MOUSE",
  },
  {
    id: "c11", corsair: 11, razer: 11, row: 2, col: 4,
    action: "Switch App", short: "⌘ Tab", description: "Hold to open the macOS App Switcher; release to choose the highlighted app.",
    signal: "keyboard", output: "native Karabiner ⌘-Tab + held ⌘", status: "PHYSICALLY ACCEPTED · RELOCATED POSITION PENDING",
  },
  {
    id: "c12", corsair: 12, razer: 10, row: 1, col: 4,
    action: "Utility", short: "Utility", description: "Open Utility immediately.",
    signal: "runtime", output: "Agentic Mouse Utility entry", status: "PHYSICALLY REPORTED WORKING · EXACT SOURCE MATRIX OPEN",
  },
];

const EXTRAS = {
  "corsair-wheel": {
    title: "Corsair wheel press", position: "Middle mouse button", corsairRaw: "pointing_button button3", razerRaw: "—",
    action: "Play / Pause", description: "Karabiner converts the ordinary middle-click source into the system Play/Pause consumer key.", signal: "media",
    output: "button3 → consumer_key_code play_or_pause", status: "KARABINER-OWNED · PHYSICALLY ACCEPTED",
  },
  "razer-wheel": {
    title: "Razer wheel press", position: "Middle mouse button", corsairRaw: "—", razerRaw: "pointing_button button3",
    action: "Play / Pause", description: "Karabiner converts the ordinary middle-click source into the same system Play/Pause consumer key.", signal: "media",
    output: "button3 → consumer_key_code play_or_pause", status: "KARABINER-OWNED · PHYSICAL ACCEPTANCE PENDING",
  },
  "corsair-dpi": {
    title: "Corsair top DPI", position: "Behind the wheel", corsairRaw: "iCUE F19 transport", razerRaw: "—",
    action: "VoiceInk++", description: "Toggle speech-to-text on physical release without changing the fixed sensor DPI.", signal: "keyboard",
    output: "F19 release → ⌃⌥⇧ · VoiceInk++ shortcut", status: "EXACT-DEVICE RULE INSTALLED · PHYSICAL ACCEPTANCE PENDING",
  },
  "razer-f21": {
    title: "Razer upper DPI", position: "Above F22", corsairRaw: "—", razerRaw: "F21",
    action: "VoiceInk++", description: "Toggle the same speech-to-text role on physical release.", signal: "keyboard",
    output: "F21 release → ⌃⌥⇧ · VoiceInk++ shortcut", status: "EXACT-DEVICE RULE INSTALLED · PHYSICAL ACCEPTANCE PENDING",
  },
  "razer-f22": {
    title: "Razer lower DPI", position: "Below the wheel", corsairRaw: "Corsair uses F19", razerRaw: "F22",
    action: "VoiceInk++", description: "Toggle the same speech-to-text role on physical release; VoiceInk++ discards only a second complete Primary chord inside 90 ms.", signal: "keyboard",
    output: "F22 release → ⌃⌥⇧ · VoiceInk++ shortcut", status: "EXACT-DEVICE RULE INSTALLED · PHYSICAL ACCEPTANCE PENDING",
  },
};

const pairById = new Map(PAIRS.map((pair) => [pair.id, pair]));
const pairByCorsair = new Map(PAIRS.map((pair) => [pair.corsair, pair]));
const pairByRazer = new Map(PAIRS.map((pair) => [pair.razer, pair]));

const state = {
  selected: pairById.has(location.hash.slice(1).toLowerCase()) ? location.hash.slice(1).toLowerCase() : "c8",
  extra: EXTRAS[location.hash.slice(1).toLowerCase()] ? location.hash.slice(1).toLowerCase() : null,
  layer: new URLSearchParams(location.search).get("layer") === "vscode" ? "vscode" : "normal",
  keyDevice: "corsair",
  selectedDevice: "corsair",
  keyOpen: false,
};

const elements = {
  body: document.body,
  stage: document.getElementById("device-stage"),
  corsairGrid: document.getElementById("corsair-grid"),
  razerGrid: document.getElementById("razer-grid"),
  keyGrid: document.getElementById("key-grid"),
  keyPanel: document.getElementById("grid-key"),
  keyToggle: document.getElementById("key-toggle"),
  keyClose: document.getElementById("key-close"),
  signalLayer: document.getElementById("signal-layer"),
  traceShadow: document.getElementById("trace-shadow"),
  traceActive: document.getElementById("trace-active"),
  traceStart: document.getElementById("trace-start"),
  traceEnd: document.getElementById("trace-end"),
  busLabel: document.getElementById("bus-label"),
  detailTitle: document.getElementById("detail-title"),
  detailPosition: document.getElementById("detail-position"),
  corsairTransport: document.getElementById("corsair-transport"),
  razerTransport: document.getElementById("razer-transport"),
  actionLayerLabel: document.getElementById("action-layer-label"),
  actionName: document.getElementById("action-name"),
  actionDescription: document.getElementById("action-description"),
  alternate: document.getElementById("alternate-action"),
  alternateName: document.getElementById("alternate-name"),
  alternateOutput: document.getElementById("alternate-output"),
  acceptanceStatus: document.getElementById("acceptance-status"),
  detailSignal: document.getElementById("detail-signal"),
  signalGlyph: document.getElementById("signal-glyph"),
  signalName: document.getElementById("signal-name"),
  signalCode: document.getElementById("signal-code"),
  signalDescription: document.getElementById("signal-description"),
  announcement: document.getElementById("selection-announcement"),
  layerNote: document.getElementById("layer-note"),
  tooltip: document.getElementById("button-tooltip"),
  tooltipAddress: document.getElementById("tooltip-address"),
  tooltipTitle: document.getElementById("tooltip-title"),
  tooltipMeta: document.getElementById("tooltip-meta"),
  tooltipOutput: document.getElementById("tooltip-output"),
};

function corsairTransport(number) {
  if (number <= 9) return `keypad_${number}`;
  if (number === 10) return "keypad_0";
  if (number === 11) return "keypad_hyphen";
  return "keypad_plus";
}

function razerTransport(number) {
  if (number <= 9) return String(number);
  if (number === 10) return "0";
  if (number === 11) return "hyphen";
  return "equal_sign";
}

function activeAction(pair, device = state.selectedDevice) {
  if (device === "razer" && pair.razerAction && !(state.layer === "vscode" && pair.vscodeAction)) return pair.razerAction;
  return state.layer === "vscode" && pair.vscodeAction ? pair.vscodeAction : pair;
}

function makeMouseKey(device, pair) {
  const number = pair[device];
  const action = activeAction(pair, device);
  const button = document.createElement("button");
  button.type = "button";
  button.className = "mouse-key";
  button.dataset.pairId = pair.id;
  button.dataset.device = device;
  button.dataset.signal = action.signal;
  button.dataset.glyph = SIGNALS[action.signal].glyph;
  button.dataset.tooltipAddress = `Corsair ${pair.corsair} ↔ Razer ${pair.razer}`;
  button.dataset.tooltipTitle = action.action;
  button.dataset.tooltipMeta = `${state.layer === "vscode" ? (pair.vscodeAction ? "VS Code · explicit override" : "VS Code · inherited base") : "Normal · global base"} · ${SIGNALS[action.signal].name}`;
  button.dataset.tooltipOutput = action.output;
  button.setAttribute("role", "radio");
  button.setAttribute("aria-checked", "false");
  button.setAttribute(
    "aria-label",
    `${device === "corsair" ? "Corsair" : "Razer"} ${number}; paired with ${device === "corsair" ? `Razer ${pair.razer}` : `Corsair ${pair.corsair}`}; ${action.action}; ${SIGNALS[action.signal].name}`,
  );
  button.innerHTML = `<span class="key-number">${number}</span><span class="key-action">${action.short}</span>`;
  button.addEventListener("click", () => selectPair(pair.id, { focus: false, device }));
  button.addEventListener("pointerenter", () => previewPair(pair.id));
  button.addEventListener("pointerenter", () => showTooltip(button));
  button.addEventListener("pointerleave", (event) => {
    restoreSelectedTrace(event);
    hideTooltip();
  });
  button.addEventListener("focus", () => showTooltip(button));
  button.addEventListener("blur", hideTooltip);
  button.addEventListener("keydown", handleGridKeydown);
  return button;
}

function physicalOrder(device) {
  return [...PAIRS].sort((a, b) => {
    if (a.row !== b.row) return a.row - b.row;
    return device === "razer" ? b.col - a.col : a.col - b.col;
  });
}

function renderMouseGrids() {
  elements.corsairGrid.replaceChildren(...physicalOrder("corsair").map((pair) => makeMouseKey("corsair", pair)));
  elements.razerGrid.replaceChildren(...physicalOrder("razer").map((pair) => makeMouseKey("razer", pair)));
}

function renderKeyGrid() {
  const order = [...PAIRS].sort((a, b) => a.row - b.row || a.col - b.col);
  const buttons = order.map((pair) => {
    const action = activeAction(pair, state.keyDevice);
    const button = document.createElement("button");
    button.type = "button";
    button.className = "key-cell";
    button.dataset.pairId = pair.id;
    const primary = state.keyDevice === "corsair" ? `C${pair.corsair}` : `R${pair.razer}`;
    const secondary = state.keyDevice === "corsair" ? `R${pair.razer}` : `C${pair.corsair}`;
    button.innerHTML = `<strong>${primary}</strong><small>${secondary} · ${action.short}</small>`;
    button.setAttribute("aria-label", `Corsair ${pair.corsair}, Razer ${pair.razer}: ${action.action}`);
    button.addEventListener("click", () => {
      selectPair(pair.id, { focus: false });
      if (matchMedia("(max-width: 759px)").matches) setKeyOpen(false);
    });
    return button;
  });
  elements.keyGrid.replaceChildren(...buttons);
}

function pairButtons(pairId) {
  return [...document.querySelectorAll(`.mouse-key[data-pair-id="${pairId}"]`)];
}

function clearPairPreviews() {
  document.querySelectorAll(".mouse-key.is-preview").forEach((button) => button.classList.remove("is-preview"));
}

function selectPair(pairId, options = {}) {
  const pair = pairById.get(pairId);
  if (!pair) return;
  clearPairPreviews();
  state.selected = pairId;
  if (options.device) state.selectedDevice = options.device;
  state.extra = null;
  document.querySelectorAll(".top-control.is-selected").forEach((button) => button.classList.remove("is-selected"));
  updateSelectionUI(pair, options);
  updateLocation(pair.id);
}

function updateSelectionUI(pair, options = {}) {
  const action = activeAction(pair, state.selectedDevice);
  const signal = SIGNALS[action.signal];
  const selectedButtons = pairButtons(pair.id);

  elements.stage.classList.add("has-selection");
  document.querySelectorAll(".mouse-key").forEach((button) => {
    const selected = button.dataset.pairId === pair.id;
    button.classList.toggle("is-selected", selected);
    button.setAttribute("aria-checked", String(selected));
    button.tabIndex = selected ? 0 : -1;
  });
  document.querySelectorAll(".key-cell").forEach((button) => button.classList.toggle("is-selected", button.dataset.pairId === pair.id));

  elements.detailTitle.innerHTML = `Corsair ${pair.corsair} <span>↔</span> Razer ${pair.razer}`;
  elements.detailPosition.textContent = `Column ${pair.col} · ${["top", "middle", "bottom"][pair.row - 1]} row`;
  elements.corsairTransport.textContent = corsairTransport(pair.corsair);
  elements.razerTransport.textContent = razerTransport(pair.razer);
  elements.actionLayerLabel.textContent = state.layer === "vscode"
    ? (pair.vscodeAction ? "VS CODE · EXPLICIT OVERRIDE" : "VS CODE · INHERITED BASE")
    : "GLOBAL BASE ACTION";
  elements.actionName.textContent = action.action;
  elements.actionDescription.textContent = action.description;
  elements.acceptanceStatus.textContent = action.status;

  elements.alternate.hidden = true;

  updateSignal(action.signal, action.output);
  elements.busLabel.textContent = `SW-C${pair.corsair} / R${pair.razer} · ${action.action}`;
  requestAnimationFrame(() => drawTrace(pair.id, true));

  const announcement = `Corsair ${pair.corsair}, Razer ${pair.razer}. ${action.action}. ${signal.name}.`;
  elements.announcement.textContent = announcement;
  if (options.focus) selectedButtons.find((button) => button.dataset.device === options.focus)?.focus();
}

function selectExtra(id) {
  const extra = EXTRAS[id];
  if (!extra) return;
  clearPairPreviews();
  state.extra = id;
  document.querySelectorAll(".top-control").forEach((button) => button.classList.toggle("is-selected", button.dataset.extra === id));
  document.querySelectorAll(".mouse-key").forEach((button) => {
    button.classList.remove("is-selected");
    button.setAttribute("aria-checked", "false");
  });
  document.querySelectorAll(".key-cell").forEach((button) => button.classList.remove("is-selected"));

  elements.detailTitle.textContent = extra.title;
  elements.detailPosition.textContent = extra.position;
  elements.corsairTransport.textContent = extra.corsairRaw;
  elements.razerTransport.textContent = extra.razerRaw;
  elements.actionLayerLabel.textContent = "CURRENT ACTION";
  elements.actionName.textContent = extra.action;
  elements.actionDescription.textContent = extra.description;
  elements.alternate.hidden = true;
  elements.acceptanceStatus.textContent = extra.status;
  updateSignal(extra.signal, extra.output);
  elements.busLabel.textContent = extra.linkPair ? "SAME ACTION · DIFFERENT CONTROL" : extra.action.toUpperCase();
  elements.announcement.textContent = `${extra.title}. ${extra.action}. ${SIGNALS[extra.signal].name}.`;
  if (extra.linkPair) {
    pairButtons(extra.linkPair).forEach((button) => button.classList.add("is-preview"));
    requestAnimationFrame(() => drawTrace(extra.linkPair, true));
  } else {
    clearTrace();
  }
  updateLocation(id);
}

function updateSignal(signalId, output) {
  const signal = SIGNALS[signalId];
  elements.detailSignal.dataset.signal = signalId;
  elements.signalGlyph.textContent = signal.glyph;
  elements.signalName.textContent = signal.name;
  elements.signalCode.textContent = output;
  elements.signalDescription.textContent = signal.description;
}

function updateLocation(hash) {
  const url = new URL(location.href);
  url.hash = hash;
  if (state.layer === "vscode") url.searchParams.set("layer", "vscode");
  else url.searchParams.delete("layer");
  history.replaceState(null, "", url);
}

function setLayer(layer) {
  if (!['normal', 'vscode'].includes(layer) || state.layer === layer) return;
  state.layer = layer;
  elements.body.dataset.layer = layer;
  document.querySelectorAll(".layer-button").forEach((button) => {
    const active = button.dataset.layer === layer;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-checked", String(active));
  });
  updateLayerNote();
  hideTooltip();
  renderMouseGrids();
  renderKeyGrid();
  if (state.extra) selectExtra(state.extra);
  else {
    updateSelectionUI(pairById.get(state.selected));
    updateLocation(state.selected);
  }
}

function updateLayerNote() {
  elements.layerNote.innerHTML = state.layer === "vscode"
    ? "<strong>VS Code base preview.</strong> Cells 5 and 8 add accepted single/double Better Git gestures; every other cell inherits Default. The deliberately entered VS Code mode has its own larger map in the main deck."
    : "<strong>Normal preview.</strong> Physical cell 5 remains Forward, cell 8 remains Back, and cell 6 rewinds the selected YouTube target by five seconds.";
}

function setKeyDevice(device) {
  state.keyDevice = device;
  state.selectedDevice = device;
  document.querySelectorAll("[data-key-device]").forEach((button) => {
    const active = button.dataset.keyDevice === device;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-checked", String(active));
  });
  renderKeyGrid();
  if (!state.extra) document.querySelector(`.key-cell[data-pair-id="${state.selected}"]`)?.classList.add("is-selected");
}

function setKeyOpen(open, { restoreFocus = false } = {}) {
  state.keyOpen = open;
  elements.keyPanel.hidden = !open;
  elements.keyToggle.setAttribute("aria-expanded", String(open));
  if (open) elements.keyClose.focus({ preventScroll: true });
  else if (restoreFocus) elements.keyToggle.focus({ preventScroll: true });
}

function previewPair(pairId) {
  if (state.extra) return;
  clearPairPreviews();
  pairButtons(pairId).forEach((button) => button.classList.add("is-preview"));
  drawTrace(pairId, false);
}

function restoreSelectedTrace(event) {
  const pairId = event?.currentTarget?.dataset?.pairId;
  if (pairId) pairButtons(pairId).forEach((button) => button.classList.remove("is-preview"));
  if (state.extra) {
    const linkPair = EXTRAS[state.extra]?.linkPair;
    if (linkPair) drawTrace(linkPair, false);
    else clearTrace();
  } else {
    drawTrace(state.selected, false);
  }
}

function drawTrace(pairId, animate) {
  const corsair = document.querySelector(`.mouse-key[data-device="corsair"][data-pair-id="${pairId}"]`);
  const razer = document.querySelector(`.mouse-key[data-device="razer"][data-pair-id="${pairId}"]`);
  if (!corsair || !razer) return;
  const stageRect = elements.stage.getBoundingClientRect();
  elements.signalLayer.setAttribute("viewBox", `0 0 ${stageRect.width} ${stageRect.height}`);
  elements.signalLayer.setAttribute("preserveAspectRatio", "none");
  const corsairRect = corsair.getBoundingClientRect();
  const razerRect = razer.getBoundingClientRect();
  const mobile = matchMedia("(max-width: 759px)").matches;
  let start;
  let end;
  let path;

  if (mobile) {
    start = { x: corsairRect.left + corsairRect.width / 2 - stageRect.left, y: corsairRect.bottom - stageRect.top };
    end = { x: razerRect.left + razerRect.width / 2 - stageRect.left, y: razerRect.top - stageRect.top };
    const midY = start.y + (end.y - start.y) / 2;
    path = `M ${start.x} ${start.y} V ${midY} H ${end.x} V ${end.y}`;
  } else {
    start = { x: razerRect.right - stageRect.left, y: razerRect.top + razerRect.height / 2 - stageRect.top };
    end = { x: corsairRect.left - stageRect.left, y: corsairRect.top + corsairRect.height / 2 - stageRect.top };
    const midX = start.x + (end.x - start.x) / 2;
    path = `M ${start.x} ${start.y} H ${midX} V ${end.y} H ${end.x}`;
  }

  elements.traceShadow.setAttribute("d", path);
  elements.traceActive.setAttribute("d", path);
  elements.traceStart.setAttribute("cx", start.x);
  elements.traceStart.setAttribute("cy", start.y);
  elements.traceEnd.setAttribute("cx", end.x);
  elements.traceEnd.setAttribute("cy", end.y);
  if (animate) {
    elements.signalLayer.classList.remove("is-drawing");
    void elements.signalLayer.getBoundingClientRect();
    elements.signalLayer.classList.add("is-drawing");
  }
}

function clearTrace() {
  elements.traceShadow.setAttribute("d", "");
  elements.traceActive.setAttribute("d", "");
  elements.traceStart.setAttribute("cx", 0);
  elements.traceStart.setAttribute("cy", 0);
  elements.traceEnd.setAttribute("cx", 0);
  elements.traceEnd.setAttribute("cy", 0);
}

function showTooltip(button) {
  if (!button?.dataset?.tooltipTitle) return;
  elements.tooltipAddress.textContent = button.dataset.tooltipAddress;
  elements.tooltipTitle.textContent = button.dataset.tooltipTitle;
  elements.tooltipMeta.textContent = button.dataset.tooltipMeta;
  elements.tooltipOutput.textContent = button.dataset.tooltipOutput;
  elements.tooltip.hidden = false;
  elements.tooltip.setAttribute("aria-hidden", "false");

  requestAnimationFrame(() => {
    const buttonRect = button.getBoundingClientRect();
    const tooltipRect = elements.tooltip.getBoundingClientRect();
    const margin = 10;
    let left = buttonRect.left + buttonRect.width / 2 - tooltipRect.width / 2;
    let top = buttonRect.top - tooltipRect.height - margin;
    left = Math.max(8, Math.min(left, innerWidth - tooltipRect.width - 8));
    if (top < 68) top = buttonRect.bottom + margin;
    elements.tooltip.style.left = `${left}px`;
    elements.tooltip.style.top = `${top}px`;
    elements.tooltip.classList.add("is-visible");
  });
}

function hideTooltip() {
  elements.tooltip.classList.remove("is-visible");
  elements.tooltip.setAttribute("aria-hidden", "true");
  elements.tooltip.hidden = true;
}

function handleGridKeydown(event) {
  const button = event.currentTarget;
  const device = button.dataset.device;
  const currentPair = pairById.get(button.dataset.pairId);
  let nextRow = currentPair.row;
  let nextCol = currentPair.col;

  if (event.key === "ArrowUp") nextRow -= 1;
  else if (event.key === "ArrowDown") nextRow += 1;
  else if (event.key === "ArrowLeft") nextCol += device === "razer" ? 1 : -1;
  else if (event.key === "ArrowRight") nextCol += device === "razer" ? -1 : 1;
  else if (event.key === "Home") nextCol = device === "razer" ? 4 : 1;
  else if (event.key === "End") nextCol = device === "razer" ? 1 : 4;
  else return;

  event.preventDefault();
  const nextPair = PAIRS.find((pair) => pair.row === nextRow && pair.col === nextCol);
  if (nextPair) selectPair(nextPair.id, { focus: device });
}

function initialize() {
  elements.body.dataset.layer = state.layer;
  updateLayerNote();
  renderMouseGrids();
  renderKeyGrid();

  document.querySelectorAll(".layer-button").forEach((button) => {
    const active = button.dataset.layer === state.layer;
    button.classList.toggle("is-active", active);
    button.setAttribute("aria-checked", String(active));
    button.addEventListener("click", () => setLayer(button.dataset.layer));
    button.addEventListener("keydown", (event) => {
      if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
      event.preventDefault();
      const next = state.layer === "normal" ? "vscode" : "normal";
      setLayer(next);
      document.querySelector(`.layer-button[data-layer="${next}"]`)?.focus();
    });
  });

  document.querySelectorAll("[data-key-device]").forEach((button) => {
    button.addEventListener("click", () => setKeyDevice(button.dataset.keyDevice));
  });
  document.querySelectorAll(".top-control").forEach((button) => {
    button.addEventListener("click", () => selectExtra(button.dataset.extra));
    const extra = EXTRAS[button.dataset.extra];
    button.dataset.tooltipAddress = extra.title;
    button.dataset.tooltipTitle = extra.action;
    button.dataset.tooltipMeta = SIGNALS[extra.signal].name;
    button.dataset.tooltipOutput = extra.output;
    button.addEventListener("pointerenter", () => showTooltip(button));
    button.addEventListener("pointerleave", hideTooltip);
    button.addEventListener("focus", () => showTooltip(button));
    button.addEventListener("blur", hideTooltip);
  });

  elements.keyToggle.addEventListener("click", () => setKeyOpen(!state.keyOpen, { restoreFocus: state.keyOpen }));
  elements.keyClose.addEventListener("click", () => setKeyOpen(false, { restoreFocus: true }));
  document.addEventListener("pointerdown", (event) => {
    if (!state.keyOpen || elements.keyPanel.contains(event.target) || elements.keyToggle.contains(event.target)) return;
    setKeyOpen(false);
  });
  document.addEventListener("keydown", (event) => {
    if (event.key.toLowerCase() === "g" && !event.metaKey && !event.ctrlKey && !event.altKey) {
      event.preventDefault();
      setKeyOpen(!state.keyOpen, { restoreFocus: state.keyOpen });
    } else if (event.key === "Escape" && state.keyOpen) {
      event.preventDefault();
      setKeyOpen(false, { restoreFocus: true });
    }
  });

  if (state.extra) selectExtra(state.extra);
  else updateSelectionUI(pairById.get(state.selected));

  let resizeFrame = 0;
  const redraw = () => {
    cancelAnimationFrame(resizeFrame);
    resizeFrame = requestAnimationFrame(restoreSelectedTrace);
  };
  addEventListener("resize", redraw, { passive: true });
  if ("ResizeObserver" in window) new ResizeObserver(redraw).observe(elements.stage);
}

initialize();
