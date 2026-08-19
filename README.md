<div align="center">

<img src="Headroom/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Headroom app icon">

# Headroom

**How much of your Claude plan is left, at a glance.**

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![WidgetKit](https://img.shields.io/badge/WidgetKit-small%20%C2%B7%20medium%20%C2%B7%20large-purple)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

A menu bar app and a desktop widget. They show how much of your Claude plan you have used, how
many tokens you have spent, and what that work would cost on the API.

Every 60 seconds Headroom asks Anthropic how much of your plan is left, and reads Claude Code's
own log files for your token counts. The menu bar shows what is left. The widget shows the same
thing on your desktop.

## What you see

**In the menu bar**, a bar for each limit: your five hour session, your week, and each per-model
cap. Each one shows how far along you are and when it resets. Below that, tokens and cost for
this session and for today, plus how fast you are spending them.

**On the desktop**, pick a size. Small shows your worst limit as a ring. Medium lists every
limit as bars. Large leads with a ring and lists the rest below it. Right click the desktop and
pick Edit Widgets, or open Notification Center, then search for "Headroom".

You can also pick which limit a widget follows, or leave it on whichever is highest.

## Notifications

You get one alert each time a limit passes 80%, 95%, and 100%, with a sound at 95% and up. They
arm themselves again when the limit resets. Turn them off from the menu bar panel.

## First run

Headroom reads your Claude Code login out of the keychain, so macOS asks you once whether to
allow it. Click Always Allow. After that it stays quiet: the 60 second poll asks in a way that
cannot open a popup, and only the refresh arrow and the Reconnect button can ever ask again.

## Install

Not packaged yet. For now, clone the repo and run `./build.sh`. Homebrew is the plan.

## Known limits

- **The widget does not really redraw every 60 seconds.** Headroom asks it to, but WidgetKit
  reloads on its own budget. The menu bar number is exact. The widget lags behind it.
- **Apple Silicon only right now.** The build is arm64, so it will not run on an Intel Mac.
- **Not notarized.** Fine on your own Mac. If someone else downloads it, Gatekeeper warns them.

## Privacy

- **Your numbers stay on your Mac.** Token counts and cost come from Claude Code's own log
  files in `~/.claude/projects/`. Headroom pulls out numbers only: how many tokens, which
  model, when, and an id it uses to skip repeats. It never keeps what you or Claude typed, and
  it never keeps which project you were in.
- **One server, one call.** Headroom talks to `api.anthropic.com` and nothing else. No update
  check, no analytics, no crash reports. The call sends your token so the server knows who is
  asking. It sends nothing else.
- **Keychain.** Headroom reads Claude Code's saved login, then keeps a copy of the token in its
  own keychain item. The token never lands on disk.
- **What it saves.** One small file holding your percentages, token counts, and cost, plus a
  few notification settings. Nothing else.
- **Why it is not sandboxed.** A sandboxed app cannot read another app's keychain item. The
  widget *is* sandboxed. It only reads that small file, and it carries none of the code that
  handles logins or reads logs.

## License

MIT, see [LICENSE](LICENSE). That covers the code in this repo. It gives you no rights to
anyone else's name, service, or data.

Headroom is a personal project. Anthropic did not build it, back it, or review it. "Claude" and
"Anthropic" are their names, not this project's.

- It reads an endpoint Anthropic has not documented. They can change or drop it any day.
- It only ever reads your own login and your own logs, on your own Mac.
- The dollar figures are what the same work would cost on the API. Your plan is a flat fee, so
  read them as a size, not a bill.
- Free to use.
- Own a right and see a problem here? Open an issue.

*No warranty. Not legal advice.*
