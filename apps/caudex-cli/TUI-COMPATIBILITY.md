# TUI compatibility and accessibility

The initial TUI is tested on the release platforms: x86_64/aarch64 Linux GNU,
Apple Silicon macOS, and x86_64 Windows GNU. It targets ordinary ANSI/VT
terminals supported by libvaxis. Other terminals and platforms are unverified.

All actions are keyboard-operable. Arrow keys have `j`/`k` alternatives,
enter/space selects, `?` or F1 opens help, escape cancels, and `q` quits. Narrow
terminals retain IDs and status text. Unicode glyphs have ASCII fallbacks.
Resize and interruption use the tested lifecycle restoration path.

Color is decorative: every status includes a textual label. `NO_COLOR` and
monochrome mode suppress styling without removing meaning. The line-oriented
CLI, including human and JSON formats, remains the accessible fallback when a
full-screen terminal is unsuitable.
