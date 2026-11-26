#!/usr/bin/env node
// Vassy hook: records the latest lifecycle event of each coding-agent session so
// the menu bar app knows who is waiting for an answer.
//
// Installed by install.sh into ~/.vassy/hook.js and registered with every agent
// the user picked, as `node hook.js <agent>`:
//   claude  Stop, Notification, UserPromptSubmit, SessionEnd
//   codex   Stop, PermissionRequest, UserPromptSubmit, PostToolUse, SessionEnd
// Writes one small JSON file per session and prints nothing, so the agent carries
// on unchanged. Never blocks: hard exit after 1.5 s, all errors swallowed.
'use strict';
if (process.env.VASSY_SUMMARIZER) process.exit(0); // the app's own summary calls

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execFileSync } = require('child_process');

setTimeout(() => process.exit(0), 1500);

const AGENTS = {
  claude: { events: ['Stop', 'Notification', 'UserPromptSubmit', 'SessionEnd'], binary: /(^|\/)claude$/ },
  codex: { events: ['Stop', 'PermissionRequest', 'UserPromptSubmit', 'PostToolUse', 'SessionEnd'], binary: /(^|\/)codex[^/]*$/ },
};
const WAITING = new Set(['Stop', 'Notification', 'PermissionRequest']);

const agent = AGENTS[process.argv[2]] ? process.argv[2] : 'claude';

// Walk up from the hook's shell: the first ancestor that owns a terminal gives the
// tty, the first one that looks like the agent binary gives the pid to watch.
function origin(pid) {
  let tty = null, agentPid = null;
  for (let i = 0; i < 6 && pid > 1; i++) {
    let out;
    try {
      out = execFileSync('/bin/ps', ['-o', 'tty=,ppid=,comm=', '-p', String(pid)], { encoding: 'utf8', timeout: 400 }).trim();
    } catch { break; }
    const m = out.match(/^(\S+)\s+(\d+)\s+(.*)$/);
    if (!m) break;
    if (!tty && /^ttys\d+$/.test(m[1])) tty = '/dev/' + m[1];
    if (!agentPid && AGENTS[agent].binary.test(m[3])) agentPid = pid;
    if (tty && agentPid) break;
    pid = parseInt(m[2], 10);
  }
  return { tty, pid: agentPid };
}

function permissionText(e) {
  const input = e.tool_input && typeof e.tool_input === 'object' ? e.tool_input : {};
  const detail = [input.description, input.command, input.file_path].find((v) => typeof v === 'string' && v) || '';
  return ('Permission needed: ' + (e.tool_name || 'tool') + (detail ? ' · ' + detail : '')).slice(0, 300);
}

let buf = '';
process.stdin.on('data', (d) => { buf += d; if (buf.length > 1e6) process.exit(0); });
process.stdin.on('end', () => {
  try {
    const e = JSON.parse(buf);
    const sid = e.session_id;
    const ev = e.hook_event_name;
    if (typeof sid !== 'string' || !/^[A-Za-z0-9_-]{8,80}$/.test(sid) || !AGENTS[agent].events.includes(ev)) return;

    const dir = path.join(os.homedir(), '.vassy', 'events');
    fs.mkdirSync(dir, { recursive: true });
    const file = path.join(dir, sid + '.json');
    let prev = {};
    try { prev = JSON.parse(fs.readFileSync(file, 'utf8')); } catch {}

    // PostToolUse only matters to end a "waiting for permission" state.
    if (ev === 'PostToolUse' && prev.event !== 'PermissionRequest') return;

    const from = prev.tty && prev.pid ? prev : origin(process.ppid);
    const tty = prev.tty || from.tty;
    // Sessions without a terminal (desktop apps, headless runs) cannot be answered from Vassy.
    if (agent !== 'claude' && !tty) return;

    const now = Date.now();
    const waiting = WAITING.has(ev);
    const out = {
      agent,
      sessionId: sid,
      cwd: typeof e.cwd === 'string' ? e.cwd : prev.cwd || null,
      transcriptPath: typeof e.transcript_path === 'string' ? e.transcript_path : prev.transcriptPath || null,
      event: ev,
      at: now,
      // a reminder after Stop keeps the original waiting time
      waitingSince: waiting ? (prev.waitingSince || now) : null,
      notification: ev === 'Notification' && typeof e.message === 'string' ? e.message.slice(0, 300)
        : ev === 'PermissionRequest' ? permissionText(e) : null,
      ended: ev === 'SessionEnd',
      tty,
      pid: prev.pid || from.pid || null,
    };
    const tmp = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(out));
    fs.renameSync(tmp, file);
  } catch {}
  process.exit(0);
});
