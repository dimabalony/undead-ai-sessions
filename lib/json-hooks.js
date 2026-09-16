// Adds, removes or finds undead's hook entries in Claude Code's settings.json or Codex's hooks.json, keeping everything
// else in the file. Runs with the JavaScript that ships with macOS, so there is nothing to install.
//   osascript -l JavaScript json-hooks.js add <file> <claude|codex> <hook path>
//   osascript -l JavaScript json-hooks.js remove <file>
//   osascript -l JavaScript json-hooks.js find <file>      prints "<Event> <command>" per entry
ObjC.import('Foundation');

const MARKER = '# undead';

// Follows a symlink, so a settings.json managed by a dotfiles repo keeps its link and the real file is edited
function resolvePath(path) {
  const fm = $.NSFileManager.defaultManager;
  let current = ObjC.unwrap($(path).stringByStandardizingPath);
  for (let i = 0; i < 8; i++) {
    const target = fm.destinationOfSymbolicLinkAtPathError(current, null);
    if (target.isNil()) break;
    const dest = ObjC.unwrap(target);
    current = dest.startsWith('/') ? dest
      : ObjC.unwrap($(ObjC.unwrap($(current).stringByDeletingLastPathComponent) + '/' + dest).stringByStandardizingPath);
  }
  return current;
}

function readText(path) {
  const text = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, null);
  return text.isNil() ? null : text.js;
}

function writeText(path, text) {
  if (!$(text).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null)) {
    throw new Error('cannot write ' + path);
  }
}

function isOurs(handler) {
  return !!handler && typeof handler.command === 'string' &&
    (handler.command.endsWith(MARKER) || /(^|\/)undead[^/]*\/(.*\/)?lib\/hook'? (claude|codex) (start|end)$/.test(handler.command));
}

function shellQuote(s) {
  return "'" + s.replace(/'/g, "'\\''") + "'";
}

function run(argv) {
  const [mode, rawPath, tool, hook] = argv;
  const path = resolvePath(rawPath);
  const text = readText(path);
  // A file that exists but is not valid JSON is never overwritten: JSON.parse throws and osascript exits non-zero
  const doc = text === null || text.trim() === '' ? {} : JSON.parse(text);
  const hooks = doc.hooks && typeof doc.hooks === 'object' ? doc.hooks : {};

  if (mode === 'find') {
    const found = [];
    for (const [event, groups] of Object.entries(hooks)) {
      for (const group of Array.isArray(groups) ? groups : []) {
        for (const handler of (group && Array.isArray(group.hooks)) ? group.hooks : []) {
          if (isOurs(handler)) found.push(event + ' ' + handler.command);
        }
      }
    }
    return found.join('\n');
  }

  for (const event of Object.keys(hooks)) {
    if (!Array.isArray(hooks[event])) continue;
    hooks[event] = hooks[event].flatMap(group => {
      if (!group || !Array.isArray(group.hooks)) return [group];
      const kept = group.hooks.filter(handler => !isOurs(handler));
      if (kept.length === group.hooks.length) return [group];
      return kept.length ? [Object.assign({}, group, { hooks: kept })] : [];
    });
    if (hooks[event].length === 0) delete hooks[event];
  }

  if (mode === 'add') {
    const events = tool === 'claude' ? { SessionStart: 'start', SessionEnd: 'end' } : { SessionStart: 'start' };
    for (const [event, arg] of Object.entries(events)) {
      (hooks[event] = hooks[event] || []).push({
        hooks: [{ type: 'command', command: `${shellQuote(hook)} ${tool} ${arg} ${MARKER}` }]
      });
    }
  } else if (mode !== 'remove') {
    throw new Error('unknown mode ' + mode);
  }

  if (Object.keys(hooks).length) doc.hooks = hooks; else delete doc.hooks;
  if (text === null && Object.keys(doc).length === 0) return '';
  writeText(path, JSON.stringify(doc, null, 2) + '\n');
  return '';
}
