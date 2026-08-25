'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const vscode = require('vscode');
const { handleUri } = require('../bridge');

const timeoutMilliseconds = 3_000;

async function waitForActiveEditor(fileName) {
  const deadline = Date.now() + timeoutMilliseconds;
  while (Date.now() < deadline) {
    if (path.basename(vscode.window.activeTextEditor?.document.uri.fsPath ?? '') === fileName) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  assert.equal(
    path.basename(vscode.window.activeTextEditor?.document.uri.fsPath ?? ''),
    fileName,
    `expected ${fileName} to become the active editor`,
  );
}

async function showFixture(fileName) {
  const uri = vscode.Uri.file(path.join(__dirname, 'fixtures', fileName));
  const document = await vscode.workspace.openTextDocument(uri);
  await vscode.window.showTextDocument(document, { preview: false });
  await waitForActiveEditor(fileName);
}

async function run() {
  const outputLines = [];
  const output = { appendLine: (line) => outputLines.push(line) };

  await showFixture('A.txt');
  await showFixture('B.txt');
  await showFixture('A.txt');

  assert.equal(
    await handleUri(
      vscode,
      output,
      vscode.Uri.parse('vscode://ethansk.agentic-mouse-vscode-bridge/cursor-history/back'),
      { focusRequired: false },
    ),
    true,
  );
  await waitForActiveEditor('B.txt');

  assert.equal(
    await handleUri(
      vscode,
      output,
      vscode.Uri.parse('vscode://ethansk.agentic-mouse-vscode-bridge/cursor-history/forward'),
      { focusRequired: false },
    ),
    true,
  );
  await waitForActiveEditor('A.txt');

  assert.deepEqual(outputLines, [
    'Executed workbench.action.navigateBack.',
    'Executed workbench.action.navigateForward.',
  ]);
}

module.exports = { run };
