# lrc_tty

`lrc_tty` is a terminal lyric viewer for any MPRIS-compatible player, talking directly to the session DBus and lrclib.net. It fetches synced or plain lyrics, keeps them cached locally, and renders a minimal TUI that highlights the current line. A raw mode is also available for scripts that just want the line matching the current playback position.

[![asciicast](https://asciinema.org/a/L7AKmoiom8G3evVR7uBDCFyja.svg)](https://asciinema.org/a/L7AKmoiom8G3evVR7uBDCFyja)

## Features

- Highlights the current lyric line with optional `[mm:ss]` timestamps.
- Works with any MPRIS player via DBus; configurable target.
- Reacts immediately to playback changes via DBus signals.
- Adjustable lyric window size (`--lines NUM`).
- Disk-backed lyric cache to avoid repeat network fetches.
- `--raw` mode for one-off lyric lookups from shell scripts.
- `--list-players` reports detected MPRIS player names for quick targeting.

## Build

This repository uses the Zig build system. Development headers for `libdbus-1` and `pkg-config` are required (usually provided by a `dbus-1` development package on your distribution).

```
zig build -Doptimize=ReleaseSafe
```

Running the TUI is done through the build runner:


```sh
zig build run -- --timestamp --lines 5
```

For raw mode:

```sh
zig build run -- --raw --timestamp
```

## Environment

- `LRC_TTY_PLAYER`: default MPRIS bus suffix (maps to `org.mpris.MediaPlayer2.<name>`, defaults to `playerctld`)
- `LRC_TTY_POLL`: refresh interval in seconds (default `0.12`)
- `LRC_TTY_CACHE`: overrides lyric cache directory

## License

GPL-v3
