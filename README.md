<div align="center">

<img src="Headroom/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Headroom app icon">

# Headroom

**How much of your Claude plan is left, at a glance.**

![macOS](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5-orange)
![WidgetKit](https://img.shields.io/badge/WidgetKit-small%20%C2%B7%20medium%20%C2%B7%20large-purple)
![License](https://img.shields.io/badge/license-MIT-green)

</div>

A menu bar app and a desktop widget. They show how much of your Claude plan you have used,
how many tokens you have spent, and what that work would cost on the API.

The app reads your Claude Code login from the keychain. Every 60 seconds it asks Anthropic
how much of your plan is left, writes the answer to a small file, and tells the widget to
redraw. The widget only reads that file. It holds none of the login code.

Headroom copies the login token into its own keychain item and reads it from there. Here is
why. Claude Code rewrites the list of who may read its keychain item every time it refreshes
the token. So every read of *that* item is a fresh chance to get a popup. An item Headroom
made trusts only Headroom, so reading it never pops. The 60 second poll also asks in a way
that cannot open a popup at all. If the copy runs out and Claude Code's item will not open
quietly, the panel shows a Reconnect button. That button and the refresh arrow are the only
things that can ever ask you for access.

## Build

```sh
cp .env.example .env    # then edit it
./build.sh
```

That builds the app, puts it in `/Applications`, and restarts it. You do not need an Apple
Developer account. `build.sh` points `DEVELOPER_DIR` at the real Xcode, because
`xcode-select` often points at CommandLineTools, and that cannot build widgets.

Run `xcodegen generate` after you add or rename a file. `build.sh` already does.

## Configuration

No secrets live in this repo. The token is read from the keychain while the app runs, kept
in a second keychain item (`<bundle id>.token`), and never written to disk, a log, or a
commit. `.env` holds build settings for your own Mac, and git ignores it, so your bundle
prefix and certificate name stay yours:

| Variable | What it is for |
| --- | --- |
| `BUNDLE_ID_PREFIX` | The reverse-DNS start of both bundle ids |
| `SIGNING_IDENTITY` | The name of your code signing certificate in the login keychain |

`Shared/Config.swift` holds the knobs: how often to poll, when to warn you, the colour
cutoffs, and the keychain name. Bundle ids are not in there on purpose. They come from the
build, and `UsageStore` works them out while the app runs.

## Signing identity

Builds are signed with a certificate you make yourself. The name can be anything. It only
has to match `SIGNING_IDENTITY` in your `.env`.

This matters more than it sounds. Ad-hoc signing builds the app's identity out of the binary
hash, so every rebuild looks like a brand new app to macOS. That throws away the keychain's
"Always Allow" and orphans any widget you placed, because chronod remembers widgets by
identity. A fixed certificate ties the identity to the certificate instead. That is what
lets both keychain grants live through a rebuild:

```
designated => identifier "<prefix>.Headroom" and certificate leaf = H"<cert-sha1>"
```

To make one on another Mac, or after this one runs out in 2036, use Keychain Access >
Certificate Assistant > Create a Certificate (type: Code Signing, self-signed). Or run:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=Headroom Local" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Apple's importer says no to OpenSSL 3 defaults. Force the old ones.
openssl pkcs12 -export -out cert.p12 -inkey key.pem -in cert.pem \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout pass:tmp123

security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P tmp123 \
  -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db cert.pem

rm -f key.pem cert.p12   # the private key lives in the keychain now
```

Check it worked with `security find-identity -v -p codesigning`.

## Adding the widget

Right click the desktop and pick Edit Widgets, or open Notification Center. Then search for
"Headroom". Small shows your worst limit as a ring. Medium lists every limit as bars. Large
leads with a ring and lists the rest below it.

## Data source

`GET https://api.anthropic.com/api/oauth/usage`, using the token from the keychain item
`Claude Code-credentials` and the header `anthropic-beta: oauth-2025-04-20`.

Anthropic has not documented this endpoint. It is what `/usage` inside Claude Code calls, and
it can change any day. `fetch-usage.sh` makes the same call from a shell, which helps when
you want to test the login on its own.

The parts that matter:

- `five_hour.utilization` and `seven_day.utilization` are percentages
- `limits[]` holds the per-model caps as `kind: "weekly_scoped"`, named in `scope.model.display_name`
- `resets_at` is ISO 8601, in UTC

Token counts and cost do not come from here. They come from Claude Code's own log files. See
[Privacy](#privacy).

## Tests

```sh
xcodegen generate
xcodebuild test -project Headroom.xcodeproj -scheme HeadroomTests \
  -destination 'platform=macOS' -enableCodeCoverage YES CODE_SIGNING_ALLOWED=NO
./scripts/coverage.sh
```

The suite compiles `Shared/` on its own, so it needs no certificate and no running app. It
covers the pricing table, the log parsing and dedup, the window maths, the response decoding,
the snapshot file, and the HTTP status paths through a stubbed session.

What it does not cover, and cannot without a real keychain: reading Claude Code's credential
item, and the token cache built on top of it. GitHub Actions runs the same commands on every
push.

## Notifications

You get one alert each time a limit passes 80%, 95%, and 100%. It plays a sound at 95% and
up. Crossings are stored in `UserDefaults` and arm themselves again when the limit resets.
Turn them off from the menu bar panel.

## Snapshot location

App Groups is the normal way for an app and its widget to share a file, but you need a paid
Apple Developer account to set one up. Without one, `UsageStore` falls back to the widget's
own folder. The app is not sandboxed, so it can still write there:

```
~/Library/Containers/<prefix>.Headroom.Widget/Data/Library/Application Support/Headroom/usage.json
```

To move to App Groups later: add the `com.apple.security.application-groups` entitlement to
both targets, put `AppGroupIdentifier` back in both Info.plists in `project.yml` as
`$(TeamIdentifierPrefix)group.<prefix>.Headroom`, and set your team. `UsageStore` picks the
group folder on its own once that key is there.

## Known limits

- **The widget does not really redraw every 60 seconds.** The app polls every 60s and asks
  WidgetKit to reload, but WidgetKit reloads on its own budget. The menu bar number is
  exact. The widget lags behind it. The 15 minute timeline is a backstop for when the app is
  not running.
- **Headroom does not refresh the login itself.** Claude Code does that. When Headroom's copy
  runs out, it reads Claude Code's keychain item again, quietly. Only if that read would open
  a popup does the panel show a Reconnect button.
- **Not notarized.** Fine on your own Mac. If someone else downloads it, Gatekeeper warns
  them until it ships another way.
- **Apple Silicon only right now.** The build is arm64, so it will not run on an Intel Mac.

## Privacy

- **Your numbers stay on your Mac.** Token counts and cost come from Claude Code's own log
  files in `~/.claude/projects/`. Headroom pulls out numbers only: how many tokens, which
  model, when, and an id it uses to skip repeats. It never keeps what you or Claude typed,
  and it never keeps which project you were in.
- **One server, one call.** Headroom talks to `api.anthropic.com` and nothing else. No update
  check, no analytics, no crash reports. The call sends your token so the server knows who is
  asking. It sends nothing else.
- **Keychain.** Headroom reads Claude Code's saved login, then keeps a copy of the token in
  its own keychain item. The 60 second poll asks in a way that cannot open a popup. Only the
  refresh arrow and the Reconnect button can. The token never lands on disk.
- **What it saves.** One small file holding your percentages, token counts, and cost, plus a
  few notification settings. Nothing else.
- **Why it is not sandboxed.** A sandboxed app cannot read another app's keychain item. The
  widget *is* sandboxed. It only reads that small file, and it carries none of the code that
  handles logins or reads logs.

## License

MIT, see [LICENSE](LICENSE). That covers the code in this repo. It gives you no rights to
anyone else's name, service, or data.

Headroom is a personal project. Anthropic did not build it, back it, or review it. "Claude"
and "Anthropic" are their names, not this project's.

- It reads an endpoint Anthropic has not documented. They can change or drop it any day. See
  [Data source](#data-source).
- It only ever reads your own login and your own logs, on your own Mac.
- The dollar figures are what the same work would cost on the API. Your plan is a flat fee, so
  read them as a size, not a bill.
- Free to use.
- Own a right and see a problem here? Open an issue.

*No warranty. Not legal advice.*
