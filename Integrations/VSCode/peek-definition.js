'use strict';

// Ethan's "second Peek jumps" means the old inline zone was left above the
// scrolled source. VS Code removes that zone at its old scroll offset. Restore
// the source's logical top before the next native Peek, never after its language
// lookup (which could otherwise undo a later user scroll).
function createPeekDefinitionCommand(vscode) {
  let request = 0;
  return async function replacePeek(args) {
    const id = ++request;
    if (args?.replace === false) {
      await vscode.commands.executeCommand('editor.action.peekDefinition');
      return;
    }
    const tab = vscode.window.tabGroups.activeTabGroup.activeTab;
    const diff = tab?.input instanceof vscode.TabInputTextDiff;
    const side = args?.diffSide;
    const uri = diff && (side === 'original' || side === 'modified')
      ? tab.input[side] : undefined;
    // Both diff sides can have undefined viewColumn. Choose the side from the
    // keybinding's native focus context, rather than mistaking it for a Peek.
    const matches = uri && vscode.window.visibleTextEditors
      .filter(e => e.document.uri.toString() === uri.toString());
    // A second group or a same-file embedded Peek can expose the same URI twice.
    // Keep native behavior rather than restoring an editor we cannot identify.
    if (matches && matches.length !== 1) {
      await vscode.commands.executeCommand('editor.action.peekDefinition');
      return;
    }
    const editor = matches ? matches[0] : vscode.window.activeTextEditor;
    if (!editor || !editor.visibleRanges.length || (diff && !uri)) return;
    const document = editor.document;
    const version = document.version;
    const selections = [...editor.selections];
    const top = editor.visibleRanges[0].start.line;
    const wasFocused = vscode.window.state.focused;
    const unchanged = () => request === id && !document.isClosed
      && document.version === version
      && vscode.window.tabGroups.activeTabGroup.activeTab === tab
      && vscode.window.visibleTextEditors.includes(editor)
      && vscode.window.state.focused === wasFocused
      && editor.selections.length === selections.length
      && editor.selections.every((s, i) => s.anchor.isEqual(selections[i].anchor)
        && s.active.isEqual(selections[i].active));

    await vscode.commands.executeCommand('closeReferenceSearch');
    if (!unchanged()) return;

    if (editor.visibleRanges[0]?.start.line !== top) {
      const scope = { uri: document.uri, languageId: document.languageId };
      const config = vscode.workspace.getConfiguration('editor', scope);
      const hidesRegions = diff && vscode.workspace.getConfiguration('diffEditor', scope)
        .get('hideUnchangedRegions.enabled', true);
      // VS Code disables sticky scroll in a diff that hides unchanged regions.
      // AtTop otherwise reserves the configured sticky/cursor-surrounding lines.
      const sticky = !hidesRegions && config.get('stickyScroll.enabled', true)
        ? config.get('stickyScroll.maxLineCount', 5) : 0;
      const margin = Math.max(sticky, config.get('cursorSurroundingLines', 0));
      const line = Math.min(document.lineCount - 1, top + margin);
      editor.revealRange(new vscode.Range(line, 0, line, 0), vscode.TextEditorRevealType.AtTop);
    }
    if (unchanged()) await vscode.commands.executeCommand('editor.action.peekDefinition');
  };
}

module.exports = { createPeekDefinitionCommand };
