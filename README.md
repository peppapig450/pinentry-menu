# pinentry-menu

`pinentry-menu` is a graphical pinentry replacement written in POSIX-compliant shell. It integrates with GnuPG by implementing the pinentry protocol and provides graphical password prompts using one of several supported runners (rofi, wofi, fuzzel).

## Features

* Compatible with the pinentry protocol (used by GnuPG and friends)
* Supports rofi, wofi, and fuzzel as graphical backends
* Wayland and X11 compatible (runner-dependent)
* Respects `PINENTRY_PROGRAM` and `PINENTRY_USER_DATA` for integration
* Drop-in replacement for `pinentry`
* Configurable and extensible shell script
* Graceful fallback when requested runner is not available

## Installation

```sh
make install PREFIX=/usr
```

To uninstall:

```sh
make uninstall PREFIX=/usr
```

## Usage

To use with GnuPG:

```sh
export PINENTRY_PROGRAM=/usr/bin/pinentry-menu
export PINENTRY_USER_DATA=rofi  # or wofi, or fuzzel
```

Or configure it in your GPG agent config:

```
pinentry-program /usr/bin/pinentry-menu
```

## Dependencies

* A supported menu runner: `rofi`, `wofi`, or `fuzzel`
* A graphical environment (`DISPLAY` or `WAYLAND_DISPLAY` must be set)

## License

MIT License. See [LICENSE](./LICENSE) for full text.
