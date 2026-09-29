# MinimizeToPrevious

A Hammerspoon Spoon that changes the macOS minimize button to do exactly what it must - Minimize the current window. Not bring forth another from the current application.

When you click the **yellow minimize button**, it:

1. Activates the previous window.
2. Minimizes the current window.

## Installation

Copy `MinimizeToPrevious.spoon` to:

```text
~/.hammerspoon/Spoons/
```

Add to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("MinimizeToPrevious")
spoon.MinimizeToPrevious:start()
```

Make sure Hammerspoon has **Accessibility** permission in macOS System Settings.

## License

MIT
