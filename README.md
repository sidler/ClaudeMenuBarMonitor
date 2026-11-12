# Claude Monitor

A macOS menu bar app that lists every Claude Code session on this machine and shows
what each one is doing: **working**, **waiting for you**, or **idle**. A popover gives
short details about the selected session.

<p align="center">
  <img src="docs/panel.png" alt="The panel, listing two sessions waiting, two working and two idle" width="420">
  <img src="docs/panel-dark.png" alt="The same panel in dark mode" width="420">
</p>

Clicking a session opens its details next to the row:

<p align="center">
  <img src="docs/detail.png" alt="A session's popover: the pending permission request, its numbers, context window and recent steps" width="840">
</p>

## Requirements

- macOS 27 or newer (the app uses Liquid Glass: `glassEffect`, `GlassEffectContainer`, `.buttonStyle(.glass)`)
- Swift 6.4 — the Command Line Tools are enough, Xcode is not required

## Install

```sh
brew tap sidler/tap
brew trust --cask sidler/tap/claude-monitor
brew install --cask claude-monitor
```

Homebrew asks you to trust a tap that is not its own before it will run anything from
it; that is what the middle line is for.

Or take the zip from the [latest release](https://github.com/sidler/ClaudeMenuBarMonitor/releases/latest),
unpack it and move `ClaudeMonitor.app` to `/Applications`. The build is signed with a
Developer ID, notarised by Apple and has the ticket stapled to the bundle, so it opens
without a Gatekeeper warning and without the network.

The app has no Dock icon (`LSUIElement`). Quit from the panel, or ⌘Q while it is open.

## Build from source

```sh
make bundle
open build/ClaudeMonitor.app
```

`make install` puts it in `/Applications`, `make run` rebuilds and restarts it. To
inspect the data layer without the UI:

```sh
.build/release/ClaudeMonitor --scan
```

## Install the hooks (recommended)

Settings (the gear in the panel) has a button for it: **Install hooks**. It also reports
whether the entries are complete and can remove them again.

Without hooks the app derives state from the transcript files alone. “Working” is reliable
that way, but “needs approval” is a guess: a pending permission prompt looks exactly like a
long-running tool call.

What the button does:

1. writes `~/.claude/monitor/hook.sh` — four lines that drop the JSON Claude Code hands the
   hook on stdin into `~/.claude/monitor/events/`; no `jq`, no Python, no network,
2. registers that script in `~/.claude/settings.json` for `Notification`, `PreToolUse`,
   `PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart` and `SessionEnd`.

Existing hooks are kept, `settings.json.bak` is written before any change, and running it
twice changes nothing. The registered path deliberately lives in the home folder rather than
inside the app bundle — it stays valid when the app is moved or replaced.

The same without the UI:

```sh
.build/release/ClaudeMonitor --hooks            # status
.build/release/ClaudeMonitor --install-hooks
.build/release/ClaudeMonitor --uninstall-hooks
```

The app reads the spooled events on every scan and clears them out: exactly the newest
event per session is kept, the rest is spent.

## The five states

Three sources, in order of authority:

1. **`~/.claude/sessions/<pid>.json`** — Claude Code's own registry of running sessions.
   Each one writes its pid, session id, project folder and a `status` it maintains itself:
   `busy`, `shell`, `idle` or `waiting`. Entries whose process is gone are ignored, so a
   crashed session cannot linger as “working”. A session that is not in the registry is not
   running, and the app will never show it as working or waiting.
2. **Hooks** — they still decide *what* a waiting session waits for: a permission prompt or
   an answer. The registry's `waitingFor` field is used when no hook event is available;
   its values are undocumented, so the hook stays the better witness.
3. **Transcripts** — everything else: the headline, the recent steps, cost and token counts,
   and the state of sessions that are no longer running.

| State | Meaning | How it is detected |
| --- | --- | --- |
| **Needs approval** | a permission prompt is pending | registry `waiting` plus a permission `Notification` hook or `waitingFor` |
| **Awaiting reply** | turn finished, Claude asked something | registry `waiting` without either |
| **Working** | a turn is running | registry `busy` or `shell` |
| **Idle** | an answer is in, nothing pending | registry `idle`, or no live process |
| **Aborted** | turn stopped or errored | error entry in the transcript, no live process |

Idle sessions are the normal case and collapsed by default — the group header shows the
count and opens on click. Sorting: waiting → working → idle, newest change first within
each group. Notifications
fire only on the transition into a waiting state, once per session and turn. Sessions with
no activity for 24 hours drop off the list.

## Terminal

Settings lets you pick the terminal used by “Open in terminal”. Terminal.app, iTerm2, Tabby,
Warp, Ghostty, kitty, Alacritty, WezTerm and Hyper are detected when installed, plus a
**custom command** with `{dir}` (shell-quoted path) and `{dirurl}` (percent-encoded path).

The difference is not cosmetic. Terminal.app and iTerm tell Launch Services they can open
folders. Tabby does not — it would launch but stay in its previous directory. For Tabby the
app therefore uses `tabby://open?directory=…`, which maps onto Tabby's own `open [directory]`
command. Terminals with neither route raise a warning in Settings that points at the custom
command, and the **Test** button opens a project folder right away so a wrong line does not
surface later.

## Usage figures

The panel shows two lines above the footer: the current five-hour block and the last seven
days. They count for the machine, not for a single session, so they appear once rather than
in every popover — what is per-session is the context window, and that stays in the popover.
The figures come from three sources:

- **Plan percentages** — the real quota figures behind `/usage`. The desktop app samples
  them into `~/Library/Application Support/Claude/plan-usage-history.json`; the app reads
  that file and shows how old the sample is. Without a sample it falls back to token counts.
- **Token counts** — summed from the transcripts, so always current, but they are *our*
  sum rather than Anthropic's accounting, which weighs models differently. Cache reads are
  excluded: they dwarf everything else and say little about the quota.
- **Reset times** — a five-hour block starts with its first request and lasts five hours,
  so the reset is derived from activity and marked with `*`. When a request was actually
  rejected, the transcript carries `quotaLimits.resetsAt`, and that exact value wins. The
  weekly anchor cannot be read locally, so no weekly reset is shown.

The scan reads whole transcripts rather than their tails and therefore runs on its own
five-minute timer. It searches the mapped files for byte patterns and only decodes the
lines that match — over 1.2 GB of transcripts that is the difference between 0.7 seconds
and over a minute.

```sh
.build/release/ClaudeMonitor --usage
```

## Menu bar symbol

Selectable in Settings, with every state previewed next to the picker. Only symbols that
stay readable at 16 pixels are offered. To render the full sheet:

```sh
.build/release/ClaudeMonitor --icon-preview /tmp/icons.png
```

## Demo data and the pictures above

A real panel means somebody's real work in it: project names, branches, the commands they
ran. The screenshots in this README are taken from fabricated sessions instead.

```sh
make demo          # the app, filled with made-up sessions
make screenshots   # redraws docs/*.png from the same data
```

`make screenshots` puts real windows on screen and photographs them with `screencapture`,
so the screen is busy for a few seconds. It has to be a real photograph: the panel has no
background of its own, and the glass it sits on is composited by the window server out of
whatever lies behind it — rendered offscreen it comes out empty. Both are debug builds
only; the shipped app has no way to reach them.

## Releasing a signed, notarised build

```sh
make release
```

This builds in release configuration, signs with the Developer ID under a hardened runtime
and a secure timestamp, submits the zip to Apple, waits, staples the ticket and then asks
Gatekeeper what another Mac would conclude. It leaves
`build/release-app/ClaudeMonitor-<version>.zip`.

Two things have to be in place first, and neither can be arranged from the Makefile:

1. A **Developer ID Application** certificate in the keychain. It comes from the paid
   Apple Developer Program — "Apple Development" is for testing and "Apple Distribution"
   is for the App Store; neither works here.
2. Notarisation credentials stored once under a profile name:

   ```sh
   xcrun notarytool store-credentials ClaudeMonitor \
     --apple-id <your-apple-id> --team-id <your-team-id> \
     --password <an app-specific password from appleid.apple.com>
   ```

   A profile stored for another app does just as well: `make release NOTARY_PROFILE=<name>`.

Publishing is three more steps: tag it, attach the zip to a GitHub release, and update
`version` and `sha256` in `Casks/claude-monitor.rb` in
[sidler/homebrew-tap](https://github.com/sidler/homebrew-tap). Take the checksum from the
file GitHub serves rather than the local zip — a wrong `sha256` fails on the user's
machine, not on yours.

## Layout

```
Sources/ClaudeMonitor/
  App/      entry point, --scan and preview modes, demo data and screenshots
  Model/    Session, SessionState
  Core/     TranscriptParser, HookEvents, HookInstaller, SessionRegistry, SessionScanner,
            FSEventWatcher, SessionStore, UsageReader, TerminalLauncher, Notifier
  UI/       MenuBarIcon, MenuBarLabel, PanelView, SessionRow, SessionDetailView,
            SettingsView, Theme
```

- **TranscriptParser** reads only the last 512 KB of a `.jsonl`. The transcripts grow to
  several megabytes, and everything shown lives at the end.
- **FSEventWatcher** watches `~/.claude/projects` and the hook spool with
  `kFSEventStreamCreateFlagFileEvents`, so changes to file contents are reported too.
  150 ms debounce, plus a safety scan every 10 seconds.
- **SessionScanner** runs off the main actor and returns `Sendable` values.
- The app only reads. It writes nothing into `~/.claude/projects` and sends nothing anywhere.

## Limits

- **Prompts and tools** in the popover count only what is in the part of the file that was
  read, not the whole session. Cost, runtime and changed lines come from the `cost-state`
  entries and cover the whole session.
- **Context window**: the figure is the prompt size of the last API call. The limit is
  assumed to be 200k and raised to 1M as soon as a measurement exceeds it.
- **Menu bar symbol**: macOS renders a SwiftUI label in `MenuBarExtra` as a template image
  and discards the color. `MenuBarIcon` therefore draws the symbol by hand as an `NSImage`
  with `isTemplate = false`. States differ in the shape of the dot (filled / ring) as well,
  not in color alone.
- **Settings window**: an accessory app does not take focus by itself, so `SettingsLink`
  opened the window behind everything else and looked like a dead button. The gear now
  activates the app and raises that window explicitly.
- No SwiftUI previews without Xcode: `@State` is a macro these days and its plugin ships
  with Xcode only. The app works without `@State` — the selection lives in `SessionStore`.

## License

MIT — see [LICENSE](LICENSE).
