#!/usr/bin/env node
// Vassy hook: records the latest lifecycle event of each Claude Code
// session so the menu bar app knows who is waiting for an answer.
// Installed by install.sh into ~/.claude/claude-queue/hook.js and registered for
// Stop, Notification, UserPromptSubmit and SessionEnd. Writes one small JSON file
// per session; never blocks Claude (hard exit after 1.5 s, all errors swallowed).
'use strict';
if (process.env.CS_SUMMARIZER) process.exit(0); // the app's own summary calls

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

setTimeout(() => process.exit(0), 1500);

const WAITING = new Set(['Stop', 'Notification']);
const KNOWN = new Set(['Stop', 'Notification', 'UserPromptSubmit', 'SessionEnd', 'SessionStart']);

function ttyOf(pid) {
  // Walk up from the hook's shell to the first ancestor that owns a terminal.
  for (let i = 0; i < 4 && pid > 1; i++) {
    try {
      const out = execFileSync('/bin/ps', ['-o', 'tty=,ppid=', '-p', String(pid)], { encoding: 'utf8', timeout: 400 }).trim();
      const [tty, ppid] = out.split(/\s+/);
      if (tty && /^ttys\d+$/.test(tty)) return '/dev/' + tty;
      pid = parseInt(ppid, 10);
    } catch { return null; }
  }
  return null;
}

let buf = '';
process.stdin.on('data', (d) => { buf += d; if (buf.length > 1e6) process.exit(0); });
process.stdin.on('end', () => {
  try {
    const e = JSON.parse(buf);
    const sid = e.session_id;
    const ev = e.hook_event_name;
    if (typeof sid !== 'string' || !/^[A-Za-z0-9-]{8,80}$/.test(sid) || !KNOWN.has(ev)) return;

    const dir = path.join(os.homedir(), '.claude', 'claude-queue', 'events');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, sid + '.json');
    let prev = {};
    try { prev = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}

    const now = Date.now();
    const waiting = WAITING.has(ev);
    const out = {
      sessionId: sid,
      cwd: typeof e.cwd === 'string' ? e.cwd : prev.cwd || null,
      transcriptPath: typeof e.transcript_path === 'string' ? e.transcript_path : prev.transcriptPath || null,
      event: ev,
      at: now,
      // a reminder Notification after Stop keeps the original waiting time
      waitingSince: waiting ? (prev.waitingSince || now) : null,
      notification: ev === 'Notification' && typeof e.message === 'string' ? e.message.slice(0, 300) : null,
      ended: ev === 'SessionEnd',
      tty: prev.tty || ttyOf(process.ppid),
    };
    const tmp = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, file);
  } catch {}
  process.exit(0);
});
