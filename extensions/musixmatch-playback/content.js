(function installAgenticMouseMusixmatchListener(globalObject) {
  "use strict";

  const controller = globalObject.AgenticMouseMusixmatchController;
  const config = globalObject.AgenticMouseMusixmatchConfig;

  if (!controller || !config?.enabled) {
    return;
  }

  document.addEventListener(
    "keydown",
    (event) => {
      controller.activateFromTrustedPress({
        event,
        locationObject: window.location,
        documentObject: document,
        config
      });
    },
    true
  );
})(globalThis);
