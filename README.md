<div align="center">

<img src="Headroom/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Headroom app icon">

# Headroom

**How much of your Claude or Codex plan is left, at a glance.**

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![WidgetKit](https://img.shields.io/badge/WidgetKit-small%20%C2%B7%20medium%20%C2%B7%20large-purple)
![License](https://img.shields.io/badge/license-MIT-green)

<img src="assets/menu-bar-panel.png" width="470" alt="The Headroom panel in the menu bar">

</div>

A menu bar app and desktop widget for seeing how much of your Claude or Codex plan you have used.
The menu bar panel also shows local token counts and estimated API cost.

Choose Claude or Codex in the panel. Every 60 seconds Headroom reads the selected provider's
limits. The menu bar and desktop widget follow that choice. Each provider keeps its own last
reading, history, and pinned menu bar limit.

## What you see

**In the menu bar**, each reported limit gets a bar with its percentage and reset time. Claude
usually reports a five hour session, a week, and per-model limits. Codex shows only the limits
your account reports. A weekly-only account gets one bar.

Below the bars are local tokens and estimated API cost for today and the active session, plus a
burn rate. If Codex has no five-hour session limit, that row reads "Last 5h" and counts local
work from the last five hours.

A small flame on a bar marks where that limit is expected to be when it resets, worked out
from how fast it has been climbing. Claude's session also uses recent local spending.
Hover it for the number. A flame sitting where the bar runs out means you are on track to hit
the limit before the reset. The flame stays hidden while nothing is moving. Headroom waits until
3% of a window has elapsed before predicting, about five hours for a weekly limit.

**On the desktop**, pick a size. Small shows your worst limit as a ring. Medium lists every
limit as bars. Large leads with a ring and lists the rest below it. Right click the desktop and
pick Edit Widgets, or open Notification Center, then search for "Headroom".

<img src="assets/desktop-widget.png" width="420" alt="The medium widget on the desktop">

You can also pick which limit a widget follows, or leave it on whichever is highest. The widget
uses the provider selected in the app. If a pinned limit is absent, it shows the highest one.

## What counts

**Bars measure plan usage.** They come from the selected provider, so Claude work on claude.ai or
in Claude Desktop counts too. Codex bars use the signed-in account's limits, not local log totals.

**Tokens and cost measure local work.** Claude reads `~/.claude/projects/`. Codex reads response
records in `~/.codex/sessions/` and `~/.codex/archived_sessions/`, or under `CODEX_HOME`. Cached
input is shown separately. Reasoning tokens are already part of output and are counted once.
Forked history and repeated responses are not counted again.

Claude Code run inside Claude Desktop logs under `~/Library/Application Support/Claude/`. It
moves the plan bars but is absent from the local figures. Codex also misses cloud work without
local records and compressed logs. It skips older `token_count` snapshots because they can
repeat or include context estimates.

Codex cost is estimated from the recorded model and standard API prices. It includes cache
writes and long-context rates, but not Fast mode premiums or tool fees. Unknown models still
count toward tokens and show N/A for cost.
Prices were checked against [OpenAI's pricing](https://developers.openai.com/api/docs/pricing)
and the [GPT-5.5](https://developers.openai.com/api/docs/models/gpt-5.5) and
[GPT-5.4](https://developers.openai.com/api/docs/models/gpt-5.4) pages on September 22, 2026.
Headroom does not read Gemini or Cursor usage.

## The sprite

Down the right of the menu bar panel is a bit of pixel art that grows with whichever limit is
closest to its cap, and turns green, orange, then red along with the bars. It is there so you
can tell how you are doing without reading a number.

Pick one in Settings:

| | |
| --- | --- |
| **Plant** | A fern. A seedling means plenty of room, a full fern means you are nearly out. |
| **Water** | Water rising up the column, with waves. Full means you are out of room. |
| **Cave** | Rock closing in from the top and bottom. The gap left is your headroom. |
| **Hourglass** | Sand draining. What is left up top is your room, the heap below is what you spent. |
| **Blocks** | Pieces falling and stacking up, tetris style. The higher the heap, the less room you have left. |

There is also a **Level** setting. **Usage** follows your real numbers. **Demo** ignores them
and sweeps the whole range on a loop, which is the only way to see much when you are sitting at
5%. The Cave in particular is nearly empty below about 40%.

## Notifications

You get one alert each time a limit passes 80%, 95%, and 100%, with a sound at 95% and up. They
arm themselves again when the limit resets. Turn them off from the menu bar panel.

## First run

For Claude, there is nothing to set up, and no keychain password to type. Headroom reads your Claude Code login
through the same `security` tool Claude Code used to save it, so macOS already trusts the
asker and leaves you alone.

The one exception is a login keychain you have locked yourself, which nothing can read
without your password, Claude Code included. Headroom holds the token until it expires
rather than re-reading it every minute, so that asks about once an hour, not once a poll.

For Codex, install a recent Codex CLI and sign in with your ChatGPT account using `codex login`.
An API-key login cannot show ChatGPT plan limits. Headroom finds the CLI on its PATH, in the
standard Homebrew locations, or inside `/Applications/Codex.app`. The CLI handles its own login.

## Settings

The gear in the panel opens Settings, or press Cmd+comma. Sprite choice and notifications live
there, with a live preview of the sprite so you can see what you are picking.

The number in the menu bar follows whichever limit is highest by default. You can pin it to one
limit instead, such as your session or a per-model cap, under Menu bar.

## Install

```sh
brew install --cask maximilianfalco/headroom/headroom-bar
```

The cask is called `headroom-bar`. Plain `headroom` in Homebrew is a different app
(Headroom by Headroom Labs, extraheadroom.com), and the two cannot be installed at
the same time since both ship a `Headroom.app`.

Headroom is signed but not notarized, so the cask clears the Gatekeeper flag for you.

Or clone the repo and run `./build.sh`.

Adding your own sprite takes one file and two lines. See `Shared/Sprites/README.md`.

## Known limits

- **The widget does not really redraw every 60 seconds.** Headroom asks it to, but WidgetKit
  reloads on its own budget. The menu bar number is exact. The widget lags behind it.
- **Not notarized.** Brew clears the Gatekeeper flag for you. If you grab the zip by hand
  instead, macOS will warn you before it opens.

## Privacy

- **Your numbers stay on your Mac.** Token counts and cost come from Claude Code's and Codex's
  local log files. Headroom pulls out numbers only: how many tokens, which
  model, when, and an id it uses to skip repeats. It never keeps your prompts, assistant
  replies, or which project you were in.
- **Provider reads.** Claude uses `api.anthropic.com`. Codex runs the installed CLI's app server
  briefly and asks `account/rateLimits/read`; the CLI contacts OpenAI. This starts no model
  turn and sends no project files or prompts. Headroom adds no analytics or crash reports.
- **Keychain.** Headroom reads Claude Code's saved login with the `security` tool, the same one
  Claude Code saves it with. It writes no copy of its own: the token is held in memory until it
  expires, and never lands on disk.
- **Codex login.** Headroom does not read or copy Codex credentials. Codex uses its own login
  store and may refresh it while reading limits.
- **What it saves.** A current snapshot for the widget, a cached snapshot per provider, and a
  day of history per provider for the flame. These hold percentages, reset times, window
  lengths, and local token counts and cost, plus notification settings. Codex limit
  keys include a hash of the account ID when returned, so account histories stay separate.
- **Why it is not sandboxed.** A sandboxed app cannot reach another app's login. The
  widget *is* sandboxed. It only reads that small file, and it carries none of the code that
  handles logins or reads logs.

## License

MIT, see [LICENSE](LICENSE). That covers the code in this repo. It gives you no rights to
anyone else's name, service, or data.

Headroom is a personal project. Anthropic and OpenAI did not build it, back it, or review it.
Their product names and logos belong to them. See [logo sources and notices](assets/provider-logos.md).

- It reads an endpoint Anthropic has not documented. They can change or drop it any day.
- It only ever reads your own login and your own logs, on your own Mac.
- The dollar figures are what the same work would cost on the API. Your plan is a flat fee, so
  read them as a size, not a bill.
- Free to use.
- Own a right and see a problem here? Open an issue.

*No warranty. Not legal advice.*
