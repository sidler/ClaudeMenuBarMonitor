# Changelog

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
