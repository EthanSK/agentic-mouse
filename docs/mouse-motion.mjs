/** Animate visible mice at 30 fps, yielding to input and resuming gently after six idle seconds. */
export function createMouseMotion(element, draw, advance, ready) {
  const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
  let visible = false, frame = 0, wakeTimer = 0, previousFrame = 0, lastDraw = 0;
  let resumeAt = 0, ramp = 0, pointerHeld = false, dirty = true;

  function schedule() {
    if (!frame && visible && !document.hidden) frame = requestAnimationFrame(tick);
  }

  function render() {
    dirty = true;
    schedule();
  }

  function tick(now) {
    frame = 0;
    if (!visible || document.hidden) return;
    const keyboardFocus = element.contains(document.activeElement) && document.activeElement.matches(":focus-visible");
    const allowed = ready() && !reducedMotion.matches && !pointerHeld && !keyboardFocus;
    const running = allowed && now >= resumeAt;
    if (!dirty && running && now - lastDraw < 1000 / 30) { schedule(); return; }
    const delta = previousFrame ? Math.min((now - previousFrame) / 1000, .1) : 0;
    previousFrame = running ? now : 0;
    if (running) {
      ramp = Math.min(1, ramp + delta);
      advance(delta * ramp); // Note: Ease back into motion without catching up for time spent paused or off-screen.
    }
    draw();
    dirty = false;
    lastDraw = now;
    clearTimeout(wakeTimer);
    if (running) schedule();
    else if (allowed) wakeTimer = setTimeout(render, Math.max(0, resumeAt - now) + 1); // Note: An idle pause needs one wake-up, not a six-second rendering loop.
  }

  function pause() {
    resumeAt = performance.now() + 6000;
    ramp = 0;
    previousFrame = 0;
    clearTimeout(wakeTimer);
    render();
  }

  function refresh() {
    cancelAnimationFrame(frame);
    clearTimeout(wakeTimer);
    frame = 0;
    previousFrame = 0;
    ramp = 0;
    render();
  }

  element.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    pointerHeld = true;
    pause();
  }, { capture: true, passive: true });
  for (const type of ["pointerup", "pointercancel"])
    window.addEventListener(type, () => {
      if (!pointerHeld) return;
      pointerHeld = false;
      pause();
    }, { passive: true }); // Note: A press can end outside the mouse before dragging has captured its pointer.
  for (const type of ["pointerenter", "pointermove", "keydown", "focusin", "focusout", "click", "wheel"])
    element.addEventListener(type, pause, { passive: true });
  new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    refresh();
  }).observe(element);
  document.addEventListener("visibilitychange", refresh);
  reducedMotion.addEventListener("change", refresh);
  return { render, pause };
}
