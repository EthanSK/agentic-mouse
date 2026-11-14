'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const { createPeekDefinitionCommand } = require('../peek-definition');
const manifest = require('../package.json');

const position = (line, character = 0) => ({ line, character,
  isEqual(other) { return this.line === other.line && this.character === other.character; } });
const selection = (anchor = 70, active = 70) => ({ anchor: position(anchor), active: position(active) });
const uri = name => ({ toString: () => name });
function harness({diff = false, sticky = true, hidden = true} = {}) {
  class TextDiff { constructor() { this.original = uri('original'); this.modified = uri('modified'); } }
  const calls = [];
  const reveals = [];
  const editor = {
    document: { uri: uri(diff ? 'original' : 'file'), languageId: 'plaintext', version: 1, lineCount: 200, isClosed: false },
    selections: [selection()], visibleRanges: [{ start: position(60) }],
    revealRange(range) { reveals.push(range.start.line); },
  };
  const other = { ...editor, document: { ...editor.document, uri: uri('modified') } };
  const tab = { input: diff ? new TextDiff() : { uri: editor.document.uri } };
  const vscode = {
    TabInputTextDiff: TextDiff,
    Range: class { constructor(line) { this.start = position(line); } },
    TextEditorRevealType: { AtTop: 2 },
    window: { activeTextEditor: diff ? other : editor, visibleTextEditors: diff ? [editor, other] : [editor],
      tabGroups: { activeTabGroup: { activeTab: tab } }, state: { focused: true } },
    workspace: { getConfiguration(section) { return { get(key, fallback) {
      return ({'stickyScroll.enabled':sticky,'stickyScroll.maxLineCount':5,
        'cursorSurroundingLines':0,'hideUnchangedRegions.enabled':hidden})[key] ?? fallback;
    } }; } },
    commands: { executeCommand: async command => {
      calls.push(command);
      if (command === 'closeReferenceSearch') {
        editor.visibleRanges = [{ start: position(78) }];
        await h.afterClose?.();
      }
    } },
  };
  const h = { vscode, editor, other, calls, reveals, tab };
  h.run = createPeekDefinitionCommand(vscode);
  return h;
}

test('restores the logical source before requesting a new definition, without a timer', async () => {
  const h = harness();
  h.vscode.commands.executeCommand = async command => {
    h.calls.push(command);
    if (command === 'closeReferenceSearch') h.editor.visibleRanges = [{start: position(78)}];
    if (command === 'editor.action.peekDefinition') assert.deepEqual(h.reveals, [65]);
  };
  await h.run();
  assert.deepEqual(h.calls, ['closeReferenceSearch','editor.action.peekDefinition']);
});

test('selects the original diff editor even when activeTextEditor reports the modified side', async () => {
  const h = harness({diff: true});
  const selections = h.editor.selections;
  await h.run({diffSide:'original'});
  assert.deepEqual(h.reveals, [60]);
  assert.strictEqual(h.editor.selections, selections);
  assert.strictEqual(h.vscode.window.tabGroups.activeTabGroup.activeTab, h.tab);
});

test('uses the modified diff side when that native context was supplied', async () => {
  const h = harness({diff: true});
  h.other.revealRange = range => h.reveals.push(['modified',range.start.line]);
  h.afterClose = () => {h.other.visibleRanges = [{start:position(78)}];};
  await h.run({diffSide:'modified'});
  assert.deepEqual(h.reveals, [['modified',60]]);
});

test('keeps native behavior when a same-file Peek or second group makes the source ambiguous', async () => {
  const h = harness({diff: true});
  h.vscode.window.visibleTextEditors.push({...h.editor});
  await h.run({diffSide:'original'});
  assert.deepEqual(h.calls, ['editor.action.peekDefinition']);
  assert.deepEqual(h.reveals, []);
});

test('does not restore when closing the old panel did not move the source', async () => {
  const h = harness();
  h.afterClose = () => {h.editor.visibleRanges = [{start:position(60)}];};
  await h.run();
  assert.deepEqual(h.reveals, []);
  assert.equal(h.calls.at(-1), 'editor.action.peekDefinition');
});

test('uses the source language override for the restoration margin', async () => {
  const h = harness();const get = h.vscode.workspace.getConfiguration;
  h.vscode.workspace.getConfiguration = (section,scope) => {
    assert.equal(scope.languageId, 'plaintext');
    assert.strictEqual(scope.uri, h.editor.document.uri);
    const config = get(section,scope);
    return {get(key,fallback) {return key === 'stickyScroll.enabled' ? false : config.get(key,fallback);}};
  };
  await h.run();assert.deepEqual(h.reveals, [60]);
});

for (const [name, change] of [
  ['a new selection', h => {h.editor.selections = [selection(71,71)];}],
  ['selection direction', h => {h.editor.selections = [selection(72,70)];}],
  ['an edit', h => {h.editor.document.version++;}],
  ['a closed document', h => {h.editor.document.isClosed = true;}],
  ['a different tab', h => {h.vscode.window.tabGroups.activeTabGroup.activeTab = {};}],
  ['window focus loss', h => {h.vscode.window.state.focused = false;}],
  ['a closed editor', h => {h.vscode.window.visibleTextEditors = [];}],
]) test(`abandons restoration and reopening after ${name}`, async () => {
  const h = harness();h.afterClose = () => change(h);
  await h.run();
  assert.deepEqual(h.calls, ['closeReferenceSearch']);assert.deepEqual(h.reveals, []);
});

test('a newer replacement cancels the older pending command', async () => {
  const h = harness();let done;
  h.afterClose = () => new Promise(resolve => {done=resolve;});
  const first = h.run();await Promise.resolve();
  h.afterClose = undefined;
  await h.run();done();await first;
  assert.equal(h.calls.filter(c => c === 'editor.action.peekDefinition').length, 1);
});

test('a fast first-Peek binding supersedes an older close in flight', async () => {
  const h = harness();let done;
  h.afterClose = () => new Promise(resolve => {done=resolve;});
  const pending = h.run();await Promise.resolve();
  const first = manifest.contributes.keybindings.find(b => b.when.includes('!referenceSearchVisible'));
  h.afterClose = undefined;
  if (first.command === 'editor.action.peekDefinition') await h.vscode.commands.executeCommand(first.command);
  else await h.run(first.args);
  done();await pending;
  assert.equal(h.calls.filter(c => c === 'editor.action.peekDefinition').length, 1);
});

test('a diff without an identified side is inert', async () => {
  const h = harness({diff:true});await h.run();assert.deepEqual(h.calls, []);
});

test('the private chord leaves keyboard Option-F12 and first Peek native', () => {
  const bindings = manifest.contributes.keybindings;
  assert.equal(bindings.length, 4);
  assert.ok(bindings.every(b => b.mac === 'ctrl+alt+cmd+f12' && b.when.includes('!isInEmbeddedEditor')));
  const first = bindings.find(b => b.args?.replace === false);
  assert.ok(first.when.includes('!referenceSearchVisible'));
  assert.ok(bindings.filter(b => b.args?.replace !== false)
    .every(b => b.when.includes('&& referenceSearchVisible')));
  assert.ok(manifest.activationEvents.includes('onCommand:agenticMouse.replacePeekDefinition'));
});
