'use strict';

const vscode = require('vscode');
const { handleUri } = require('./bridge');

function activate(context) {
  const output = vscode.window.createOutputChannel('Agentic Mouse');
  context.subscriptions.push(output);
  context.subscriptions.push(vscode.window.registerUriHandler({
    handleUri: (uri) => handleUri(vscode, output, uri),
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
