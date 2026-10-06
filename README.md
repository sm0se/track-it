# TrackIt

A Raycast-style macOS panel for tasks, meetings, demos, deliverables and notes.
Native Swift/SwiftUI, no dependencies. Press **⌥T** anywhere to open it.

## Build & install

```sh
./scripts/build.sh            # → build/TrackIt.app
./scripts/build.sh --install  # → /Applications/TrackIt.app, then launches it
```

Needs only the Xcode Command Line Tools (Swift 5.9+), macOS 14+.

## Quick add

Type into the top bar and press ↵. New items take the current tab's type unless prefixed.

| Syntax | Meaning |
|---|---|
| `task:` `meet:` `demo:` `del:` `note:` | type |
| `tomorrow 3pm`, `next fri`, `oct 12` | date / time |
| `!high` `!!` `!low` | priority |
| `#client` | tag |
| `30m`, `1h` | meeting length |
| `every day`, `every weekday`, `every week`, `every mon wed fri` | repeat |
| a URL | join link |

## Keys

`↑↓` move · `↵` complete / join / open · `⌘↵` edit · `⌘S` status · `⌘P` priority · `⌘J` join ·
`⌘⌫` delete · `⌘Z` undo · `⌘1–6` / `Tab` tabs · `⌘N` new note · `⌘,` settings · `esc` back / hide

## Data

`~/Library/Application Support/TrackIt/data.json`, saved automatically.

## Dev

Debug builds accept `TRACKIT_DATA_DIR=<dir>` (use a sandbox data folder) and
`TRACKIT_SNAPSHOT=<dir>` (render every tab to PNGs, then quit):

```sh
swift build && TRACKIT_DATA_DIR=/tmp/ti TRACKIT_SNAPSHOT=/tmp/ti .build/debug/TrackIt
```
