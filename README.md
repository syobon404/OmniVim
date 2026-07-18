# OmniVim

Vim-style text editing and keyboard-driven UI navigation across macOS.

OmniVim is an experimental menu-bar app that brings modes, motions, operators, and
Vimium-style hints to native text fields and selected terminal programs. It identifies the
focused editing session, chooses an application-specific execution adapter, and yields control to
programs that already provide their own modal editing.

> [!IMPORTANT]
> OmniVim is an early prototype. Accessibility behavior varies between macOS applications, and
> terminal support is currently focused on Kitty, fish, and `agy`. Telegram visual hints require
> Screen Recording permission and are processed entirely on-device.

## Highlights

- Start each focused editor in Insert mode; hold `j`, then press `k` to enter Normal mode.
- Navigate with `h`, `j`, `k`, `l`, `w`, `b`, `0`, and `$`.
- Compose operators and motions such as `dw`, `db`, `d$`, `cw`, and `cc`.
- Press `Control-F` to label and activate accessible controls without reaching for the mouse.
- Discover Telegram chats and controls by combining Accessibility, Apple Vision, and a
  Telegram-specific layout profile.
- Keep mode state scoped to the focused editor or terminal foreground process.
- Bypass Vim, Neovim, Helix, and Kakoune so native modal input remains untouched.
- Fail open when a target or terminal session cannot be identified reliably.

## Compatibility

| Surface | Status | How OmniVim interacts with it |
| --- | --- | --- |
| Native macOS text fields | Supported | Synthesized macOS editing and selection shortcuts |
| Accessible buttons, links, menus, and rows | Partial | Accessibility actions with role-specific fallbacks |
| Chromium and Electron controls | Partial | Depends on the application's Accessibility and event bridge |
| Telegram Desktop | Experimental | GPA-GUI visual detection and coordinate activation |
| WeChat Desktop | Experimental | GPA-GUI visual detection and coordinate activation |
| Lark | Early adapter | Electron profile exists; coverage still depends on the UI exposed through Accessibility |
| Kitty + fish prompt | Supported | Kitty session detection plus a fish `commandline` companion |
| Kitty + `agy` | Experimental | Readline-style keyboard adapter |
| Vim, Neovim, Helix, and Kakoune | Bypassed | Input is returned to the program unchanged |
| SSH, unknown shells, and unknown TUIs | Pass-through | OmniVim remains inactive rather than guessing |
| Other terminal emulators | Not yet integrated | Terminal window detection exists, but foreground-program resolution is Kitty-specific |

## Quick start

### 1. Build the app

OmniVim currently ships as a development build. Xcode is required.

```sh
git clone git@github.com:syobon404/OmniVim.git
cd OmniVim
./scripts/build-app.sh
open OmniVim.app
```

The script builds the canonical Xcode target and places `OmniVim.app` in the repository root.

### 2. Grant Accessibility permission

Open the OmniVim menu-bar item and choose **Open Accessibility Settings**, then enable OmniVim in
**Privacy & Security → Accessibility**. This permission is required for cross-application focus,
UI discovery, global keyboard observation, and synthesized input.

For stable authorization across rebuilds, select your Personal Team under the OmniVim target's
**Signing & Capabilities** settings. Ad-hoc signatures may cause macOS to treat a rebuilt app as a
new executable.

### 3. Try text editing

1. Focus a text field in an app such as Notes.
2. Type normally in Insert mode.
3. Hold `j`, then press `k`; the mode pill should change to **NORMAL**.
4. Try `w`, `b`, or `dw`.
5. Press `i` or `a` to return to Insert mode.

The exit chord is ordered: `j` must already be held when `k` is pressed. A standalone `j` remains
ordinary text input.

### 4. Try UI hints

Press `Control-F` to label visible buttons, links, menu items, rows, and editable controls. Type a
hint code to narrow the overlay; the final target activates automatically. `Backspace` removes one
prefix character and `Esc` dismisses the overlay.

Hint codes are prefix-free and variable length. Markers are deduplicated before layout and rendered
in one transparent panel per display.

### Telegram and WeChat visual hints

Telegram and WeChat expose little of their main interface as useful AX controls. For normal UI
hints, OmniVim captures the current application window and runs the GPA-GUI YOLO detector locally:

```text
Messaging app front window
        │
        ├── ScreenCaptureKit
        ▼
 Salesforce GPA-GUI Detector (Core ML)
        │
        ├── confidence and geometry filtering
        ▼
 detected global frames → hint code → center click
```

The detector runs on every normal `Control-F` invocation, so it follows the current layout instead
of relying on OCR-derived rows or fixed toolbar offsets. Orange outlines expose the exact boxes
accepted by the detector. Before clicking, OmniVim waits until the target app is actually
frontmost, moves the pointer, and sends a Hammerspoon-compatible 200 ms mouse down/up sequence.
Screenshots are processed in memory and are not saved. Text-only hint search continues to use
Accessibility.

The first Telegram or WeChat hint request prompts for **Privacy & Security → Screen Recording** if
access has not already been granted. Visual detection is unavailable without it.

## Commands

### Modes and hints

| Input | Result |
| --- | --- |
| Hold `j`, then press `k` | Insert → Normal |
| `i` / `a` | Normal → Insert |
| `Esc` | Cancel a pending operator or dismiss hints; otherwise pass through to macOS |
| `Control-F` | Show hints for accessible UI elements |
| Menu → **Search UI elements** | Open searchable hints without reserving `s` |

### Motions and operators

| Command | Native text | fish | `agy` | Meaning |
| --- | :---: | :---: | :---: | --- |
| `h` / `l` | ✓ | ✓ | ✓ | Move left or right by one character |
| `j` / `k` | ✓ | ✓ | ✓ | Move down or up by one line/history entry |
| `w` / `b` | ✓ | ✓ | ✓ | Move forward or backward by one word |
| `0` / `$` | ✓ | ✓ | ✓ | Move to the start or end of the line |
| `dh` / `dl` | ✓ | ✓ | ✓ | Delete one character left or right |
| `dw` / `db` | ✓ | ✓ | ✓ | Delete forward or backward by one word |
| `d0` / `d$` | ✓ | ✓ | ✓ | Delete to the start or end of the line |
| `dd` | ✓ | ✓ | ✓ | Delete the current line or input buffer |
| `ch`, `cl`, `cw`, `cb`, `c0`, `c$`, `cc` | ✓ | ✓ | ✓ | Delete the matching range and enter Insert mode |
| `dj` / `dk`, `cj` / `ck` | ✓ | — | — | Cross-line operation; terminal semantics are not implemented |

OmniVim implements a focused subset of Vim rather than emulating a complete Vim text buffer.
Exact word and line behavior is delegated to each adapter and may differ slightly from native Vim.

## Application-aware modes

Vim mode belongs to the focused editing session, not to the whole system. When focus changes,
OmniVim starts the appropriate session in its initial mode and resets incomplete operators.

```text
Focused control or terminal process
                 │
                 ▼
        Classify editing surface
                 │
       ┌─────────┼──────────┬──────────────┐
       ▼         ▼          ▼              ▼
 Native text   fish       agy        Native modal / unknown
       │         │          │              │
 Synthetic     fish      Readline       Bypass or
 executor    companion    adapter        pass-through
```

This boundary prevents Normal mode from leaking from one app, text field, Kitty window, or terminal
foreground process into another.

## Terminal integration

Terminal command lines are not exposed as native macOS text buffers. OmniVim therefore asks Kitty
which process owns the focused window and selects an adapter for that program.

### Configure Kitty session detection

Add the following to `kitty.conf`, then fully restart Kitty:

```conf
allow_remote_control socket-only
listen_on unix:/tmp/omnivim-kitty-{kitty_pid}
```

The local Unix socket is used to resolve the focused Kitty window and foreground process. If the
socket is unavailable or the program is unknown, OmniVim leaves keyboard input untouched.

### Install the fish companion

```sh
./scripts/install-fish-integration.sh
```

Open a new fish session after installation. For each supported command, OmniVim writes a private
command file under `~/Library/Caches/OmniVim/` and sends a reserved `F20` trigger. The companion
consumes the command and edits the real buffer through fish's `commandline` API.

If fish configuration is managed declaratively, add
`Integrations/fish/conf.d/omnivim.fish` to that configuration instead of running the installer.

### Foreground-program policy

- `fish` uses the shell companion.
- `agy` uses the experimental Readline-style adapter.
- Vim, Neovim, Helix, and Kakoune bypass OmniVim completely.
- Other shells, SSH sessions, and unknown TUIs pass through unchanged.
- Changing the Kitty window or foreground PID starts a fresh editing session.

## Troubleshooting

### The mode pill does not appear

Confirm that OmniVim is running and enabled under **Privacy & Security → Accessibility**. Focus a
supported editable control; the pill intentionally stays hidden when the current surface is
inactive or unsupported. Insert mode also auto-hides after a short confirmation animation in most
apps.

### `j` + `k` does not enter Normal mode

Press and hold `j`, then press `k` before releasing `j`. The chord is not a sequential `jk` timeout.
If the app does not expose a focused editable element through Accessibility, OmniVim remains
inactive.

### Terminal commands do not work

Verify all of the following:

1. Kitty was fully restarted after adding the remote-control socket settings.
2. A new fish session was opened after installing the companion.
3. The foreground program is `fish` or `agy` rather than an unsupported shell or TUI.
4. `~/Library/Caches/OmniVim/fish-companion-ready` exists when testing fish.

### Neovim still receives OmniVim behavior

Check that Kitty session detection is working. Until the foreground program has been resolved,
OmniVim deliberately remains inactive. The diagnostic log should identify `nvim` as `nativeModal`.

### A hint moves the pointer but does not activate a control

Some controls report a successful Accessibility action without changing application state.
System Settings rows require selection semantics, while some Chromium/Electron controls reject
Accessibility or externally synthesized clicks. Telegram and WeChat use coordinate activation and
wait for the target application to become frontmost before posting the click. Check the diagnostic log for
`coordinate waiting`, `mouse move`, and the matching mouse `phase=down` / `phase=up` entries.

### Telegram or WeChat visual hints do not appear

Enable OmniVim under **Privacy & Security → Screen Recording**, then restart OmniVim. The log should
contain `Telegram GPA-only scan` or `WeChat GPA-only scan`, a non-zero `raw` count, and
`screenPermission=true`. The `captureMs`, `modelLoadMs`, `inferenceMs`, and `totalMs` fields expose
the cold and warm latency directly.

### Diagnostic files

```text
~/Library/Logs/OmniVim.log
~/Library/Logs/OmniVim/Snapshots/
```

The main log rotates at approximately 2 MiB. Debug builds expose **Open Compatibility Lab** in the
menu-bar menu; use it while the target app is frontmost to inspect capabilities and export a
redacted compatibility artifact.

## Development

Open `OmniVim.xcodeproj`, select the `OmniVim` scheme, and run on **My Mac**. The Xcode app target,
with bundle identifier `com.omnivim.app`, is the canonical development and Accessibility-debugging
surface. `Package.swift` remains available as a lightweight compiler and test harness.

Run the test suite with Xcode (`Command-U`) or:

```sh
./scripts/test.sh
```

Build the signed development app used for manual testing with:

```sh
./scripts/build-app.sh
```

### Source layout

- `App`: application lifecycle and top-level coordination.
- `ApplicationIntegration`: capability model, probes, reusable mechanisms, app-specific profiles,
  terminal adapters, and runtime adapter selection.
- `Vim`: mode engine, operator/motion parsing, command execution, and mode presentation.
- `Input`: global key monitoring and synthesized keyboard or mouse input.
- `Accessibility`: shared scanning and low-level Accessibility operations.
- `Activation`: target activation policy and fallback sequencing.
- `Hints`: pure hint code, visibility, deduplication, and layout engines.
- `UI`: hint overlay panels and markers.
- `Research/CompatibilityLab`: capability inspection, AX snapshots, and redacted compatibility
  artifacts used to research new app adapters.
- `Diagnostics`: diagnostic logging.

The coordinator owns interaction flow. `ApplicationAdapterRegistry` selects an app profile, each
profile declares capabilities rather than branching inside the coordinator, and UI components
report selected targets through an adapter-owned activation strategy. Terminal adapters translate
the same Vim command model into the editing primitives offered by each foreground program.

## Roadmap

- Expand the Vim command grammar and operator/motion coverage.
- Add adapters for more shells, terminal emulators, and coding-agent TUIs.
- Detect and bypass additional applications with native modal editing.
- Improve verified activation for Chromium and Electron accessibility targets.
- Replace Telegram and WeChat layout constants with dynamically calibrated visual controls where
  practical.
- Make mode-switch chords, indicators, and application policies user-configurable.
- Introduce richer text-buffer context without sacrificing low resource usage.

See [TODO.md](TODO.md) for confirmed limitations and current activation experiments.

## Thanks

OmniVim is informed by the work and ideas in these projects:

- [VimMode.spoon](https://github.com/dbalatero/VimMode.spoon) for demonstrating system-wide Vim
  motions and operators on macOS, including Accessibility-backed and keyboard-fallback strategies.
- [CodeMirror Vim](https://github.com/replit/codemirror-vim) for its composable Vim command,
  operator, motion, and key-mapping model.
- [VSCodeVim](https://github.com/VSCodeVim/Vim) for its extensive Vim emulation behavior and
  operator-pending mode semantics.
- [Vimac](https://github.com/nchudleigh/vimac) for its native Swift implementation of macOS
  Accessibility-driven hints and keyboard navigation.

Thank you to their maintainers and contributors for making their work available to study and learn
from. OmniVim does not imply endorsement by or affiliation with these projects.
