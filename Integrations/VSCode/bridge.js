'use strict';

const EXTENSION_ID = 'ethansk.agentic-mouse-vscode-bridge';
const TERMINAL_HIDE_COMMAND = 'workbench.action.closePanel';
const TERMINAL_SHOW_COMMAND = 'workbench.action.terminal.focus';

const routes = new Map([
  ['/cursor-history/back', 'workbench.action.navigateBack'],
  ['/cursor-history/forward', 'workbench.action.navigateForward'],
]);
let nextTerminalCommand = TERMINAL_HIDE_COMMAND;

function routeForUri(uri) {
  if (!uri || uri.scheme !== 'vscode' || uri.authority !== EXTENSION_ID) {
    return null;
  }
  if (uri.path === '/health') {
    return { kind: 'health' };
  }
  if (uri.path === '/terminal/toggle') {
    return { kind: 'terminalToggle' };
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

  const command = route.kind === 'terminalToggle' ? nextTerminalCommand : route.command;
  if (route.kind === 'terminalToggle') {
    // VS Code's toggle shortcut focuses an already-visible Terminal before it hides it. Start with the explicit close command, then alternate with explicit focus/show so one mouse press always performs the advertised step. (Codex task: 01a039f7-873c-7c30-b3dc-af8a6724ace5)
    nextTerminalCommand = command === TERMINAL_HIDE_COMMAND
      ? TERMINAL_SHOW_COMMAND
      : TERMINAL_HIDE_COMMAND;
  }

  await vscode.commands.executeCommand(command);
  output.appendLine(`Executed ${command}.`);
  return true;
}

module.exports = {
  EXTENSION_ID,
  handleUri,
  routeForUri,
};
