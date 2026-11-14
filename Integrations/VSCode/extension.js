'use strict';

const vscode = require('vscode');
const { handleUri } = require('./bridge');
const { createPeekDefinitionCommand } = require('./peek-definition');

function activate(context) {
  const output = vscode.window.createOutputChannel('Agentic Mouse');
  context.subscriptions.push(output);
  context.subscriptions.push(vscode.commands.registerCommand(
    'agenticMouse.replacePeekDefinition', createPeekDefinitionCommand(vscode)));
  context.subscriptions.push(vscode.window.registerUriHandler({
    handleUri: (uri) => handleUri(vscode, output, uri),
  }));
}

function deactivate() {}

module.exports = { activate, deactivate };
