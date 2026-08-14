import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import vm from "node:vm";

const controllerSource = await readFile(
  new URL("../controller.js", import.meta.url),
  "utf8"
);
const context = vm.createContext({});
vm.runInContext(controllerSource, context);
const controller = context.AgenticMouseMusixmatchController;

function makeEvent(overrides = {}) {
  return {
    code: "F21",
    altKey: false,
    ctrlKey: false,
    metaKey: false,
    shiftKey: false,
    isTrusted: true,
    repeat: false,
    prevented: false,
    stopped: false,
    preventDefault() {
      this.prevented = true;
    },
    stopImmediatePropagation() {
      this.stopped = true;
    },
    ...overrides
  };
}

function makeElement(name, overrides = {}) {
  return {
    disabled: false,
    clicked: false,
    textContent: "",
    ownerDocument: {
      defaultView: {
        getComputedStyle: () => ({ display: "block", visibility: "visible" })
      }
    },
    getAttribute(attribute) {
      if (attribute === "aria-label") return name;
      if (attribute === "aria-disabled") return "false";
      return null;
    },
    getClientRects: () => [{}],
    click() {
      this.clicked = true;
    },
    ...overrides
  };
}

function makeConfig(overrides = {}) {
  return {
    enabled: true,
    transport: { code: "F21" },
    target: {
      selector: '[data-testid="whole-song-playback"]',
      accessibleNames: ["Play", "Pause"]
    },
    ...overrides
  };
}

test("manifest is limited to the exact Musixmatch Pro origin", async () => {
  const manifest = JSON.parse(
    await readFile(new URL("../manifest.json", import.meta.url), "utf8")
  );

  assert.deepEqual(manifest.content_scripts.map((entry) => entry.matches), [
    ["https://pro.musixmatch.com/*"]
  ]);
  assert.equal(Object.hasOwn(manifest, "permissions"), false);
  assert.equal(Object.hasOwn(manifest, "host_permissions"), false);
  assert.equal(Object.hasOwn(manifest, "commands"), false);
});

test("the checked-in configuration is deliberately inert", async () => {
  const configSource = await readFile(
    new URL("../runtime-config.js", import.meta.url),
    "utf8"
  );
  const configContext = vm.createContext({});
  vm.runInContext(configSource, configContext);

  assert.equal(configContext.AgenticMouseMusixmatchConfig.enabled, false);
  assert.equal(configContext.AgenticMouseMusixmatchConfig.transport, null);
  assert.equal(configContext.AgenticMouseMusixmatchConfig.target, null);
});

test("trusted exact transport activates one semantic whole-song control", () => {
  const element = makeElement("Play");
  const documentObject = { querySelectorAll: () => [element] };
  const event = makeEvent();

  const activated = controller.activateFromTrustedPress({
    event,
    locationObject: { origin: controller.allowedOrigin },
    documentObject,
    config: makeConfig()
  });

  assert.equal(activated, true);
  assert.equal(element.clicked, true);
  assert.equal(event.prevented, true);
  assert.equal(event.stopped, true);
});

test("untrusted, repeating and wrong transports fail closed", () => {
  const documentObject = { querySelectorAll: () => [makeElement("Play")] };

  for (const event of [
    makeEvent({ isTrusted: false }),
    makeEvent({ repeat: true }),
    makeEvent({ code: "F22" })
  ]) {
    assert.equal(
      controller.activateFromTrustedPress({
        event,
        locationObject: { origin: controller.allowedOrigin },
        documentObject,
        config: makeConfig()
      }),
      false
    );
    assert.equal(event.prevented, false);
  }
});

test("an unrelated origin is a no-op even if called directly", () => {
  const element = makeElement("Play");
  const event = makeEvent();

  assert.equal(
    controller.activateFromTrustedPress({
      event,
      locationObject: { origin: "https://www.google.com" },
      documentObject: { querySelectorAll: () => [element] },
      config: makeConfig()
    }),
    false
  );
  assert.equal(element.clicked, false);
  assert.equal(event.prevented, false);
});

test("missing, ambiguous or wrong semantic targets fail closed", () => {
  for (const elements of [
    [],
    [makeElement("Play"), makeElement("Pause")],
    [makeElement("Play current line")]
  ]) {
    const event = makeEvent();
    assert.equal(
      controller.activateFromTrustedPress({
        event,
        locationObject: { origin: controller.allowedOrigin },
        documentObject: { querySelectorAll: () => elements },
        config: makeConfig()
      }),
      false
    );
    assert.equal(event.prevented, false);
  }
});
