# Changelog

## 1.0.3

- The plan percentages are live again, and this time they are Anthropic's own. Claude Code
  hands its status line a JSON payload carrying `rate_limits.five_hour` and
  `rate_limits.seven_day` — the percentage used and the exact reset — and Settings now has
  an **Install bridge** button that keeps a copy of that payload for the app. Hooks never
  carry those figures, and the sample the desktop app writes can be days old.
- A status line already in use is chained, not replaced: the bridge runs the previous
  command with the same input and prints its output, so the line looks unchanged.
- Both windows now begin where Anthropic says they do — `resets_at` minus five hours, and
  minus seven days — so the tokens counted and the percentage beside them describe the same
  window. The weekly reset is shown for the first time; it cannot be read anywhere else on
  the machine.

## 1.0.2

- Plan percentages are left out once they no longer describe the window they stand beside.
  The desktop app samples them rarely — days can pass — and a five-hour percentage taken
  before the current block began belongs to a block that has since reset. The five-hour
  figure now needs a sample from inside the current block, the weekly one a sample less
  than a day old. Otherwise the row shows the locally counted tokens, which are always
  current, and says how old the sample is.

## 1.0.1

- The panel no longer draws a focus ring. SwiftUI gives the first control in a window
  keyboard focus as it opens, which put a blue ring around the gear every time the panel
  appeared. It is a menu surface, and macOS draws no focus ring in a menu.

## 1.0

First release.

- Lists every Claude Code session on the machine in the menu bar, grouped into
  **waiting for you**, **working** and **idle**. Idle sessions are collapsed by default.
- State comes from three sources in order of authority: Claude Code's own session
  registry in `~/.claude/sessions`, the hook events the app spools, and the transcripts.
- A popover per session: what it is waiting for, model, runtime, prompts, cost, changed
  lines, tool calls, the context window and the last few steps — with buttons to open the
  project in a terminal, copy a `claude --resume` command or reveal the folder.
- The five-hour block and the last seven days are shown once for the machine, from the
  plan percentages the desktop app samples, with token counts as a fallback.
- Settings: the menu bar symbol, hook installation and removal, the terminal to use,
  notifications and launch at login.
- Notifications fire only on the transition into a waiting state, once per session and turn.
- Signed with a Developer ID, notarised and stapled; installable with Homebrew.
