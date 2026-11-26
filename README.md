# Vassy

A queue for your coding-agent sessions, in the macOS menu bar.

When you run several Claude Code or Codex sessions in parallel, each one eventually
stops and waits for you. Vassy notices, boils the session down to one question and a
recommendation, and types your answer into the right Terminal tab.

Website: <https://vassy.app>

## What it does

- Lists every session that is waiting on you, oldest first.
- Shows what the session is about, the one thing it needs, and a recommendation.
- Offers up to three ready-made answers on `⌘1` `⌘2` `⌘3`, or you dictate or type your own.
- Marks answers that would ship something to production.
- Sends the answer to the session's Terminal tab, or brings that tab to the front.
- Opens from anywhere with `⌥⌘C`.

## Requirements

- macOS 15 or later, with Terminal.app
- Claude Code and/or Codex CLI, signed in

## Install

Download the latest `Vassy.zip` from the
[releases page](https://github.com/sukramb/vassy/releases/latest), move `Vassy.app` into
your Applications folder and open it. The app is signed and notarized. On first launch
it asks which agents it should watch.

Or build it from source (needs the Xcode Command Line Tools, Swift 6):

```sh
git clone https://github.com/sukramb/vassy.git
cd vassy && ./install.sh
```

Either way, Vassy registers a small hook with each agent you picked:

| Agent       | Config file changed       |
| ----------- | ------------------------- |
| Claude Code | `~/.claude/settings.json` |
| Codex       | `~/.codex/hooks.json`     |

Each file is backed up to `~/.vassy/backups` first. Codex only runs hooks you have
approved: start `codex`, type `/hooks` and trust the Vassy entries.

You can change the selection later under gear menu › Agents…. From source, without
questions: `./install.sh --agents claude,codex`. To remove every hook entry:
`./install.sh --uninstall`, or `~/.vassy/hook --uninstall` for a downloaded app.

## How it works

1. **Hook.** The agents call `~/.vassy/hook`, a link to the app's own binary, when a
   session finishes a turn, asks for permission, gets a new prompt or ends. It writes
   one small JSON file per session to `~/.vassy/events` and prints nothing, so the
   agent is not affected.
2. **Summary.** The app reads the tail of the session's transcript and asks a CLI you
   already have for a compact JSON summary: `claude -p` on the small model, or
   `codex exec` if only Codex is installed. The call runs with tools and MCP servers
   switched off, and the transcript is passed as data, not as instructions.
3. **Answer.** Your reply is typed into the session's Terminal tab through AppleScript.
   macOS asks once for permission to control Terminal.

## Privacy

Vassy has no server, no account and no analytics. The only place a transcript is sent
is the agent CLI that produced it, on the login you already use. All state lives in
`~/.vassy`.

## Configuration

Both files are optional and live in `~/.vassy`.

`projects.json` groups sessions under your own project names. Without it, sessions are
grouped by the name the summarizer derives or by their folder.

```json
[
  { "name": "Storefront", "hint": "online shop, checkout, pricing", "match": ["storefront"] },
  { "name": "Atlas API", "hint": "public REST API", "match": ["atlas"] }
]
```

`match` lists keywords looked for in the session's folder path; `hint` helps the
summarizer assign sessions that run elsewhere.

`config.json` is written by the installer:

| Key          | Meaning                                                             |
| ------------ | ------------------------------------------------------------------- |
| `agents`     | Agents picked at install time                                       |
| `summarizer` | `"claude"` or `"codex"`; default is whichever CLI is installed      |
| `language`   | Language of the summaries, e.g. `"German"`; default is the system language |
| `codexModel` | Model for Codex summaries; default is your Codex default            |

## Limits

- Terminal.app only. Sessions in other terminals or in desktop apps are not listed
  for Codex, and cannot be answered for Claude Code.
- Claude Code's list of live sessions is read from an undocumented folder
  (`~/.claude/sessions`); if that format changes, liveness falls back to a time limit.

## Development

```sh
./build.sh                 # build and install for this Mac (ad-hoc signed)
scripts/release.sh         # signed, notarized universal build in dist/
```

The website is the static page in `site/`.

## License

MIT, see [LICENSE](LICENSE). The fonts in `site/fonts` are under the SIL Open Font
License; their license texts are in the same folder.

---

Vassy is a product of Heartly Apps UG (haftungsbeschränkt). It is an independent project, not affiliated with or endorsed by Anthropic or OpenAI.
