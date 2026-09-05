/** Browser-only state for the native mode graph exported by agentic-mouse-site. */
export class MouseSimulator {
  constructor(map) {
    this.map = map;
    this.app = "codex";
    this.hand = "corsair";
    this.states = Object.fromEntries(
      Object.keys(map.sources).map((source) => [source, this.initialState()]),
    );
  }

  initialState() {
    return {
      mode: "default",
      followsApp: false,
      legend: true,
      selected: 4,
      held: null,
      wheelUsed: false,
      output: "Try a button",
      text: "",
      pending: null,
      shift: this.map.initialShift,
      history: [],
    };
  }

  get state() {
    return this.states[this.hand];
  }
  get mode() {
    const source = this.map.sources[this.hand];
    return this.state.mode === "default"
      ? source.defaults[this.app]
      : source.modes[this.state.mode];
  }
  control(cell) {
    return this.mode.controls.find((control) => control.cell === cell);
  }
  rows() {
    return this.map.sources[this.hand].rows;
  }

  /** Match the app's independent left/right coordinators while sharing frontmost-app context. */
  chooseHand(hand) {
    this.hand = hand;
  }
  chooseApp(app) {
    this.app = app;
    for (const state of Object.values(this.states)) {
      state.held = null;
      state.pending = null; // The native keypad cancels pending text when the target app changes.
      if (state.followsApp) state.mode = app;
    }
  }

  /** Direct mode shortcuts are just a way to explore; cell transitions come from the exported graph. */
  chooseMode(mode, followsApp = false) {
    this.state.mode = mode;
    this.state.followsApp = followsApp;
    this.state.held = null;
    this.state.pending = null;
    if (mode === "keypad") this.state.shift = this.map.initialShift;
    this.state.output = this.mode.title;
  }

  reset() {
    this.states[this.hand] = this.initialState();
  }

  /** Enter the exact destination discovered from a native press, or demonstrate its local effect. */
  press(cell, now = performance.now()) {
    this.tick(now);
    this.state.selected = cell;
    const control = this.control(cell);
    if (!control.wheel) {
      this.state.held = null;
      this.state.wheelUsed = false;
    }
    if (control.next) {
      this.chooseMode(
        control.next,
        control.followsApp ?? this.state.followsApp,
      );
    } else if (control.keypad) {
      this.type(control.keypad, cell, now);
    } else if (control.wheel) {
      this.state.held = this.state.held === cell ? null : cell;
      this.state.wheelUsed = false;
      this.state.output = this.state.held
        ? `Holding ${control.printed} · ${control.title}`
        : "Button released";
    } else if (control.effect === "toggleLegend") {
      this.state.legend = !this.state.legend;
      this.state.output = this.state.legend
        ? "Default legend shown"
        : "Default legend hidden";
    } else if (control.title === "Spare") {
      this.state.output = "No action here";
    } else {
      this.record(control.effect ?? control.title);
    }
  }

  /** Expose a held gesture explicitly so mouse, touch and keyboard visitors can all try it. */
  hold(cell, now = performance.now()) {
    this.state.selected = cell;
    const control = this.control(cell);
    if (control.keypad) {
      this.commitPending();
      if (control.keypad.digit) this.state.text += control.keypad.digit;
      else this.typeCommand(control.keypad.hold);
      this.state.output = this.state.text || " ";
    } else if (control.wheel) {
      this.state.held = cell;
      this.state.wheelUsed = false;
      this.state.output = `Holding ${control.printed} · ${control.title}`;
    }
  }
  release() {
    this.state.held = null;
    this.state.wheelUsed = false;
    this.state.output = "Button released";
  }

  /** The exported labels resolve wheel direction and one-action-per-hold behaviour in Swift. */
  wheel(direction) {
    const control =
      this.state.held === null ? null : this.control(this.state.held);
    if (!control?.wheel) return;
    const action = control.wheel[direction];
    if (control.wheel.oncePerHold && this.state.wheelUsed) {
      this.state.output = "Release and hold again";
      return;
    }
    if (!action) {
      this.state.output = "No action in this direction";
      return;
    }
    this.state.wheelUsed = true;
    this.record(action);
  }

  doublePress(cell) {
    const control = this.control(cell);
    if (control.doublePress)
      this.record(control.doublePress.replace(/([a-z])([A-Z])/g, "$1 $2"));
  }

  record(action) {
    this.commitPending();
    const keyText = {
      insertSpace: " ",
      pressBackspace: "Backspace",
      arrowLeft: "←",
      arrowRight: "→",
      arrowUp: "↑",
      arrowDown: "↓",
      undo: "Undo",
    };
    if (action === "insertSpace") this.state.text += " ";
    if (action === "pressBackspace")
      this.state.text = this.state.text.slice(0, -1);
    this.state.output = keyText[action] ?? action;
    this.state.history = [...this.state.history.slice(-3), this.state.output];
  }

  /** Use native key groups and timing; the browser owns only the disposable text example. */
  type(key, cell, now) {
    if (!key.cycle.length) {
      this.commitPending();
      this.typeCommand(key.tap);
      return;
    }
    const pending = this.state.pending;
    if (pending?.cell !== cell) this.commitPending();
    const index =
      pending?.cell === cell ? (pending.index + 1) % key.cycle.length : 0;
    let character = key.cycle[index];
    if (this.state.shift === "initialCaps" || this.state.shift === "upper")
      character = character.toUpperCase();
    this.state.pending = {
      cell,
      index,
      character,
      deadline: now + this.map.keypadTimeout,
    };
    this.state.output = this.state.text + character;
  }

  typeCommand(command) {
    const action = command ? Object.keys(command)[0] : null;
    if (action === "space") this.state.text += " ";
    if (action === "newline") this.state.text += "\n";
    if (action === "backspace") this.state.text = this.state.text.slice(0, -1);
    this.state.output = this.state.text || " ";
  }
  commitPending(state = this.state) {
    if (!state.pending) return;
    state.text += state.pending.character;
    state.pending = null;
    if (state.shift === "initialCaps") state.shift = "lower";
  }
  tick(now = performance.now()) {
    for (const state of Object.values(this.states)) {
      if (state.pending && now >= state.pending.deadline) {
        this.commitPending(state);
        state.output = state.text;
      }
    }
  }
}
