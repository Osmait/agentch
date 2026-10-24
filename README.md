# Notch Hub

A tiny macOS app that lives in your MacBook's notch and shows how much of your AI coding subscriptions you have left.

Hover over the notch and it springs open with the 5-hour and weekly limits for each agent, when each window resets and how long until it does. Move the pointer away and it folds back into an empty notch.

<p align="center">
  <img src="docs/images/panel.png" alt="Notch Hub open, showing Claude Code, Codex and Antigravity limits" width="620">
</p>

## Supported subscriptions

| Agent | Plan shown | Where the data comes from |
| --- | --- | --- |
| **Claude Code** | Pro / Max | Anthropic's OAuth usage endpoint, using the token Claude Code stores in the login Keychain |
| **Codex** | Plus / Pro | `codex app-server` (`account/rateLimits/read`) |
| **Antigravity** | Gemini, and Claude & GPT pools | `agy -p /usage --output-format json` |

Every provider reads from the official CLI or credentials you already have on your Mac. Notch Hub has no account and no servers, and it doesn't depend on any third-party tool.

Bars turn amber once a window passes 80 %. Data refreshes every two minutes, and again when you open the panel if it is older than 30 seconds.

## Requirements

- macOS 14 or later (a Mac with a notch looks best; other displays get a notch-sized area under the menu bar)
- Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Whichever CLIs you want to track, signed in: `claude`, `codex`, `agy`

## Build and run

```sh
xcodegen generate
xcodebuild -project NotchHub.xcodeproj -scheme NotchHub -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/NotchHub.app
```

`project.yml` signs with an Apple Development identity so the Keychain "Always Allow" survives rebuilds. Change `DEVELOPMENT_TEAM` to your own team ID.

Right-click the panel for **Refresh Now** and **Quit Notch Hub**. To keep the panel open while working on the UI:

```sh
open build/Build/Products/Debug/NotchHub.app --args -pinOpen YES
```

Logs:

```sh
/usr/bin/log show --last 5m --info --predicate 'subsystem == "com.saulburgos.notchhub"'
```

## Project layout

```
NotchHub/
  App/        App entry point and delegate
  Notch/      Notch geometry, panel window, hover handling and animated shape
  Limits/     The expanded view: provider rows, limit bars, formatting
  Usage/      UsageStore, models and one provider per subscription
```

Adding a subscription means writing a type that conforms to `UsageProvider` and adding it to the list in `AppDelegate`.
