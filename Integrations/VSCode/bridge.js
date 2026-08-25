'use strict';

const EXTENSION_ID = 'ethansk.agentic-mouse-vscode-bridge';

const routes = new Map([
  ['/cursor-history/back', 'workbench.action.navigateBack'],
  ['/cursor-history/forward', 'workbench.action.navigateForward'],
]);

function routeForUri(uri) {
  if (!uri || uri.scheme !== 'vscode' || uri.authority !== EXTENSION_ID) {
    return null;
  }
  if (uri.path === '/health') {
    return { kind: 'health' };
  }
  const command = routes.get(uri.path);
  return command ? { kind: 'command', command } : null;
}

async function handleUri(vscode, output, uri, options = {}) {
  const route = routeForUri(uri);
  if (!route) {
    output.appendLine('Rejected an unknown Agentic Mouse URI.');
    return false;
  }
  if (route.kind === 'health') {
    output.appendLine('Agentic Mouse VS Code Bridge is ready.');
    return true;
  }

  const focusRequired = options.focusRequired !== false;
  if (focusRequired && !vscode.window.state.focused) {
    output.appendLine(`Rejected ${route.command}: this VS Code window is not focused.`);
    return false;
  }

  await vscode.commands.executeCommand(route.command);
  output.appendLine(`Executed ${route.command}.`);
  return true;
}

module.exports = {
  EXTENSION_ID,
  handleUri,
  routeForUri,
};
