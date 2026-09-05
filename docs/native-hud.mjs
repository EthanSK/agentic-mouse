/** Project browser state into the native HUD's card hierarchy; Swift owns the labels, colour roles and border metrics. */
export function hudPresentation(simulator) {
  const { state, mode, hand, map } = simulator;
  const keypad = state.mode === "keypad";
  const pending = state.pending;
  const shifted = state.shift === "initialCaps" || state.shift === "upper";
  return {
    visible: state.mode !== "default" || state.legend,
    style: mode.presentationStyle,
    color: mode.color,
    title: mode.title,
    source: map.sources[hand].name,
    feedback: state.feedback,
    status: keypad
      ? pending
        ? `${pending.character}  ·  tap ${pending.index + 1} of ${simulator.control(pending.cell).keypad.cycle.length}`
        : "Ready"
      : state.feedback ?? mode.title,
    shift: { lower: "abc", initialCaps: "Abc", upper: "ABC", numeric: "123" }[state.shift],
    cards: simulator.rows().flat().map((cell) => {
      const control = simulator.control(cell);
      const selected = keypad ? pending?.cell === cell : state.mode !== "default" && state.hudSelection === cell;
      const treatment = selected ? map.hud.selected : control.destinationColor ? map.hud.navigation : map.hud.ordinary;
      return {
        cell,
        title: control.title,
        printed: control.printed,
        label: `${hand === "razer" ? "Razer" : "Corsair"} ${control.printed}${control.reportedBroken ? " ❌" : ""}`,
        selected,
        held: state.held === cell,
        navigation: Boolean(control.destinationColor),
        ...control.hud,
        appIcon: control.appIcon,
        borderWidth: treatment.width,
        borderOpacity: treatment.opacity,
        fillOpacity: mode.presentationStyle === "neutral" && !control.destinationColor ? (selected ? .58 : .24) : 1,
        cycle: control.keypad?.cycle.map((character) => shifted ? character.toUpperCase() : character) ?? [],
        activeCycleIndex: pending?.cell === cell ? pending.index : null,
        holdCaption: control.keypad?.holdCaption,
      };
    }),
  };
}

/** Keep the same twelve focusable nodes while a mouse press replaces the mode, just like the non-activating native reference panel. */
export function createNativeHUD(element, simulator, { activate, bindHold, keydown, preview }) {
  element.classList.add("native-hud");
  const grid = document.createElement("div");
  grid.className = "native-hud-grid";
  grid.setAttribute("role", "group");
  grid.setAttribute("aria-label", "HUD controls");
  const footer = document.createElement("div");
  footer.className = "native-hud-footer";
  const status = document.createElement("span");
  if (element.id === "mouse-hud") status.setAttribute("role", "status"); // Both previews update together; announce each change once rather than reading the off-screen duplicate too.
  const source = document.createElement("span");
  const shift = document.createElement("span");
  footer.append(status, shift, source);
  element.replaceChildren(grid, footer);
  const buttons = new Map();
  for (const cell of simulator.rows().flat()) {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "native-hud-card";
    button.dataset.cell = cell;
    button.addEventListener("click", () => activate(cell, button));
    button.addEventListener("keydown", (event) => keydown(event, cell, buttons));
    button.addEventListener("focus", () => preview(cell));
    button.addEventListener("pointerenter", () => preview(cell));
    bindHold(button, cell);
    buttons.set(cell, button);
  }
  return () => {
    const hud = hudPresentation(simulator);
    element.hidden = !hud.visible;
    element.dataset.style = hud.style;
    element.style.setProperty("--hud-accent", hud.color);
    element.style.setProperty("--hud-card-inset", `${simulator.map.hud.cardInset / 6.51}cqw`);
    grid.setAttribute("aria-label", `${hud.source} · ${hud.title}`);
    for (const [position, card] of hud.cards.entries()) {
      const button = buttons.get(card.cell);
      button.setAttribute("aria-label", `${card.label}: ${card.title}`);
      button.setAttribute("aria-pressed", String(card.selected));
      button.classList.toggle("is-held", card.held);
      button.classList.toggle("is-exit", simulator.control(card.cell).next === "default");
      button.style.setProperty("--card-fill", card.fill);
      button.style.setProperty("--card-border", card.border);
      button.style.setProperty("--card-foreground", card.foreground);
      button.style.setProperty("--card-opacity", `${card.fillOpacity * 100}%`);
      button.style.setProperty("--card-border-opacity", `${card.borderOpacity * 100}%`);
      button.style.setProperty("--card-border-width", `${card.borderWidth / 6.51}cqw`);
      button.classList.toggle("has-app-icon", Boolean(card.appIcon));
      button.style.setProperty("--app-icon", card.appIcon ? `url("./assets/apps/${card.appIcon}.png")` : "none");
      const title = document.createElement("span");
      title.className = "native-hud-title";
      title.textContent = hud.style === "keypad" ? card.printed : card.title;
      const label = document.createElement("span");
      label.className = "native-hud-label";
      label.textContent = card.label;
      button.replaceChildren(title);
      if (hud.style === "keypad") {
        const cycle = document.createElement("span");
        cycle.className = `native-hud-cycle${card.cycle.length > 6 ? " is-dense" : ""}`;
        for (const [index, character] of card.cycle.entries()) {
          const letter = document.createElement("span");
          letter.textContent = character;
          letter.classList.toggle("is-current", index === card.activeCycleIndex);
          cycle.append(letter);
        }
        if (!card.cycle.length) cycle.textContent = card.title;
        button.append(cycle);
        if (card.holdCaption) {
          const hold = document.createElement("span");
          hold.className = "native-hud-hold";
          hold.textContent = card.holdCaption;
          button.append(hold);
        }
      }
      button.append(label);
      if (grid.children[position] !== button) grid.insertBefore(button, grid.children[position] ?? null);
    }
    status.textContent = hud.style === "keypad" ? `${hud.title} · ${hud.status}` : hud.status;
    status.classList.toggle("has-feedback", Boolean(hud.feedback));
    source.textContent = hud.style === "keypad" ? "" : `${hud.source} · ${simulator.map.version}`;
    shift.textContent = hud.style === "keypad" ? hud.shift : "";
  };
}
