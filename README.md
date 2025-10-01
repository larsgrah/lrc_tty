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

## Installation

### From source

This repository uses the Zig build system. Development headers for `libdbus-1` and `pkg-config` are required (usually provided by a `dbus-1` development package on your distribution).

```sh
zig build -Doptimize=ReleaseSafe
```

The resulting binary is placed under `zig-out/bin/lrc_tty`. You can add that directory to your `PATH` or install manually where you prefer.

Run the TUI straight from the build runner:

```sh
zig build run -- --timestamp --lines 5
```

For raw mode:

```sh
zig build run -- --raw --timestamp
```

### Arch Linux (AUR)

An AUR package is available at `ssh://aur.archlinux.org/lrc_tty.git`. Clone it and build with `makepkg`:

```sh
git clone ssh://aur.archlinux.org/lrc_tty.git
cd lrc_tty
makepkg -si
```
or use your favourite aur helper like yay: 

```sh
yay -S lrc_tty
```

### Void Linux

A Void Linux template lives in `https://github.com/larsgrah/void-custom/tree/master`.

```sh
git clone https://github.com/larsgrah/void-custom.git
cd void-custom
./xbps-src pkg lrc_tty
xi lrc_tty
```

## Environment

- `LRC_TTY_PLAYER`: default MPRIS bus suffix (maps to `org.mpris.MediaPlayer2.<name>`, defaults to `playerctld`)
- `LRC_TTY_POLL`: refresh interval in seconds (default `0.12`)
- `LRC_TTY_CACHE`: overrides lyric cache directory

## License

GPL-v3
