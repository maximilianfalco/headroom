# Headroom

Menu bar app plus a macOS widget showing current usage against your Claude plan limits.

The app (unsandboxed) reads the Claude Code OAuth token from the keychain, polls the usage
endpoint every 60 seconds, writes a snapshot, and pushes a widget reload. The widget
(sandboxed) only reads that snapshot, and does not compile any credential handling.

The token is copied into Headroom's own keychain item and re-read from there until it
expires. Claude Code rewrites the access list on its item every time it refreshes its
token, so every read of *that* item is another chance to be prompted for access, while an
item Headroom created trusts only Headroom. The poll loop can never raise a dialog: it
asks for the token with interaction disabled, and if the copy has expired and Claude Code's
item will not open silently, the panel shows a Reconnect button instead. Pressing it, or
the refresh arrow, is the only thing that can prompt.

## Build

```sh
cp .env.example .env    # then edit it
./build.sh
```

Builds, installs to `/Applications`, and relaunches. No Apple Developer account or
provisioning profile is needed. `build.sh` pins `DEVELOPER_DIR` to the real Xcode, since
`xcode-select` often points at CommandLineTools, which cannot build app extensions.

Run `xcodegen generate` after adding or renaming files (build.sh already does).

## Configuration

There are no secrets in this repo. The OAuth token is read from the keychain at runtime,
cached in a second keychain item (`<bundle id>.token`), and is never written to disk,
logged, or committed. `.env` holds only per-machine build settings, and is gitignored so
your bundle prefix and certificate name stay local:

| Variable | Purpose |
| --- | --- |
| `BUNDLE_ID_PREFIX` | Reverse-DNS prefix for both bundle identifiers |
| `SIGNING_IDENTITY` | Name of the code signing certificate in your login keychain |

Runtime behaviour lives in `Shared/Config.swift`: poll interval, notification thresholds,
the severity cutoffs used for colour, the reset notice floor, and the keychain service name.
Bundle identifiers are deliberately not in there, since they come from the build and are
derived at runtime by `UsageStore`.

## Signing identity

Builds are signed with a self-signed local certificate. The name is arbitrary and only
has to match `SIGNING_IDENTITY` in your `.env`. This
matters more than it sounds: ad-hoc signing derives the app's identity from the binary
hash, so every rebuild produces a different identity. That invalidates the keychain ACL
entry behind "Always Allow" and orphans placed widgets, because chronod caches extensions
by code identity. A fixed certificate pins the designated requirement to the cert instead, which is what lets
both the "Always Allow" grant on Claude Code's item and Headroom's own token item survive a
rebuild:

```
designated => identifier "<prefix>.Headroom" and certificate leaf = H"<cert-sha1>"
```

To recreate it on another machine (or after it expires in 2036), either use Keychain Access
> Certificate Assistant > Create a Certificate (type: Code Signing, self-signed), or:

```sh
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 3650 -nodes \
  -subj "/CN=Headroom Local" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Apple's importer rejects OpenSSL 3 defaults, so force the legacy algorithms.
openssl pkcs12 -export -out cert.p12 -inkey key.pem -in cert.pem \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 -passout pass:tmp123

security import cert.p12 -k ~/Library/Keychains/login.keychain-db -P tmp123 \
  -T /usr/bin/codesign -T /usr/bin/security
security add-trusted-cert -r trustRoot -p codeSign \
  -k ~/Library/Keychains/login.keychain-db cert.pem

rm -f key.pem cert.p12   # the private key now lives in the keychain
```

Confirm with `security find-identity -v -p codesigning`.

## Adding the widget

Right click the desktop > Edit Widgets, or open Notification Center, then search for
"Headroom". Small shows the single worst limit as a ring; medium lists every limit as
bars.

## Data source

`GET https://api.anthropic.com/api/oauth/usage`, with the OAuth access token from the
keychain item `Claude Code-credentials` and header `anthropic-beta: oauth-2025-04-20`.

This endpoint is undocumented and is what `/usage` inside Claude Code calls. It can change
without notice. `fetch-usage.sh` is a standalone shell implementation of the same call,
useful for verifying auth outside the app.

Response shape that matters:

- `five_hour.utilization` and `seven_day.utilization` are percentages
- `limits[]` carries per-model caps as `kind: "weekly_scoped"` with `scope.model.display_name`
- `resets_at` is ISO 8601 UTC

## Notifications

Fires once per threshold crossing (80%, 95%, 100%) per limit, with sound at 95% and above.
Crossings are tracked in `UserDefaults` and rearm automatically when a limit resets. Toggle
them off from the menu bar panel.

## Snapshot location

App Groups is the idiomatic way to share data between an app and its widget, but it
requires a paid Apple Developer account to provision. Without one, `UsageStore` falls back
to the widget extension's own container, which the unsandboxed app can still write to:

```
~/Library/Containers/<prefix>.Headroom.Widget/Data/Library/Application Support/Headroom/usage.json
```

To switch to App Groups later: add the `com.apple.security.application-groups` entitlement
to both targets, re-add `AppGroupIdentifier` to both Info.plists in `project.yml` as
`$(TeamIdentifierPrefix)group.<prefix>.Headroom`, and set your team. `UsageStore`
prefers the group container automatically when the key is present.

## Known constraints

- **Widget refresh is not really every 60 seconds.** The app polls at 60s and calls
  `WidgetCenter.reloadAllTimelines()`, but WidgetKit refreshes on a system budget. The menu
  bar number is exact; the widget lags behind it. The timeline policy is a 15 minute
  safety net for when the app is not running.
- **Token refresh is not implemented.** Claude Code refreshes the keychain item itself. If
  the token expires the app surfaces "Token expired, open Claude Code to refresh".
- **Ad-hoc signing means no notarization.** Fine locally. Moving this to another Mac would
  need real signing.
