'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { EXTENSION_ID, handleUri, routeForUri } = require('../bridge');

function uri(path, overrides = {}) {
  return {
    scheme: 'vscode',
    authority: EXTENSION_ID,
    path,
    ...overrides,
  };
}

function harness(focused = true) {
  const commands = [];
  const output = [];
  return {
    commands,
    output,
    vscode: {
      window: { state: { focused } },
      commands: {
        executeCommand: async (command) => commands.push(command),
      },
    },
    channel: { appendLine: (line) => output.push(line) },
  };
}

test('accepts only the exact extension authority and allow-listed paths', () => {
  assert.deepEqual(routeForUri(uri('/cursor-history/back')), {
    kind: 'command',
    command: 'workbench.action.navigateBack',
  });
  assert.equal(routeForUri(uri('/cursor-history/back', { authority: 'other.extension' })), null);
  assert.equal(routeForUri(uri('/cursor-history/back', { scheme: 'https' })), null);
  assert.equal(routeForUri(uri('/command/workbench.action.closeWindow')), null);
  assert.deepEqual(routeForUri(uri('/terminal/toggle')), {
    kind: 'terminalToggle',
  });
  assert.deepEqual(routeForUri(uri('/codex/add-to-chat')), {
    kind: 'command',
    command: 'chatgpt.addToThread',
  });
});

test('health activates the bridge without executing an editor command', async () => {
  const h = harness(false);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/health')), true);
  assert.deepEqual(h.commands, []);
  assert.match(h.output[0], /ready/);
});

test('executes VS Code Back and Forward through the command API', async () => {
  const h = harness(true);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/cursor-history/back')), true);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/cursor-history/forward')), true);
  assert.deepEqual(h.commands, [
    'workbench.action.navigateBack',
    'workbench.action.navigateForward',
  ]);
});

test('starts the Terminal alternator with Hide, then alternates Show and Hide', async () => {
  const h = harness(true);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/terminal/toggle')), true);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/terminal/toggle')), true);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/terminal/toggle')), true);
  assert.deepEqual(h.commands, [
    'workbench.action.closePanel',
    'workbench.action.terminal.focus',
    'workbench.action.closePanel',
  ]);
});

test('fails closed when the receiving VS Code window is not focused', async () => {
  const h = harness(false);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/cursor-history/back')), false);
  assert.deepEqual(h.commands, []);
  assert.match(h.output[0], /not focused/);
});

test('adds the retained editor selection to Codex while VS Code is in the background', async () => {
  const h = harness(false);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/codex/add-to-chat')), true);
  assert.deepEqual(h.commands, ['chatgpt.addToThread']);
});

test('rejects unknown actions without executing arbitrary command ids', async () => {
  const h = harness(true);
  assert.equal(await handleUri(h.vscode, h.channel, uri('/cursor-history/delete-all')), false);
  assert.deepEqual(h.commands, []);
  assert.match(h.output[0], /Rejected/);
});
