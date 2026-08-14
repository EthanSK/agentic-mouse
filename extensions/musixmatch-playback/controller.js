(function installAgenticMouseMusixmatchController(globalObject) {
  "use strict";

  const allowedOrigin = "https://pro.musixmatch.com";

  function normaliseName(element) {
    const rawName =
      element.getAttribute?.("aria-label") ??
      element.getAttribute?.("title") ??
      element.textContent ??
      "";

    return rawName.trim().replace(/\s+/g, " ").toLowerCase();
  }

  function isUsable(element) {
    if (!element || element.disabled) {
      return false;
    }

    if (element.getAttribute?.("aria-disabled") === "true") {
      return false;
    }

    const style = element.ownerDocument?.defaultView?.getComputedStyle?.(element);
    if (style && (style.display === "none" || style.visibility === "hidden")) {
      return false;
    }

    if (typeof element.getClientRects === "function" && element.getClientRects().length === 0) {
      return false;
    }

    return true;
  }

  function eventMatchesTransport(event, transport) {
    if (!transport || event.isTrusted !== true || event.repeat === true) {
      return false;
    }

    return (
      event.code === transport.code &&
      event.altKey === Boolean(transport.altKey) &&
      event.ctrlKey === Boolean(transport.ctrlKey) &&
      event.metaKey === Boolean(transport.metaKey) &&
      event.shiftKey === Boolean(transport.shiftKey)
    );
  }

  function findUniqueSemanticTarget(documentObject, target) {
    if (!target?.selector || !Array.isArray(target.accessibleNames) || target.accessibleNames.length === 0) {
      return null;
    }

    const allowedNames = new Set(target.accessibleNames.map((name) => name.trim().toLowerCase()));
    const matches = Array.from(documentObject.querySelectorAll(target.selector)).filter(
      (element) => isUsable(element) && allowedNames.has(normaliseName(element))
    );

    return matches.length === 1 ? matches[0] : null;
  }

  function activateFromTrustedPress({ event, locationObject, documentObject, config }) {
    if (!config?.enabled || locationObject.origin !== allowedOrigin) {
      return false;
    }

    if (!eventMatchesTransport(event, config.transport)) {
      return false;
    }

    const target = findUniqueSemanticTarget(documentObject, config.target);
    if (!target) {
      return false;
    }

    event.preventDefault();
    event.stopImmediatePropagation();
    target.click();
    return true;
  }

  globalObject.AgenticMouseMusixmatchController = Object.freeze({
    activateFromTrustedPress,
    allowedOrigin,
    eventMatchesTransport,
    findUniqueSemanticTarget,
    normaliseName
  });
})(globalThis);
