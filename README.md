# OmniVim

OmniVim is a macOS menu-bar prototype that combines Vim-style text navigation with Homerow-style accessibility hints.

## MVP interactions

- `h` / `j` / `k` / `l`: arrow-key navigation while an editable AX element is focused.
- `w` / `b`: option-right / option-left word jumps.
- `i` / `a`: leave OmniVim's normal mode and return to regular typing.
- `Esc`: return to normal mode or dismiss hints.
- `Control-F`: scan buttons, links, menu items and editable controls in the frontmost app.
- Search hints are available from the menu; `s` remains a normal input key.

UI hints use Vimium-style variable-length codes. Typing narrows the visible markers; the last
remaining marker activates automatically. `Backspace` removes one prefix character and `Esc`
dismisses the overlay. Markers are rendered in one transparent panel per display.

The app requires Accessibility permission because macOS only exposes cross-app focus, UI hierarchy and global keyboard events through that permission.

## Development

Open `OmniVim.xcodeproj`, select the `OmniVim` scheme and run on My Mac. This is a real macOS
application target with the fixed bundle identifier `com.omnivim.app`; do not open `Package.swift`
for Accessibility debugging.

The project currently uses ad-hoc “Sign to Run Locally” because no Apple Development identity is
installed. For stable Accessibility authorization across rebuilds, select your Personal Team in
the OmniVim target's Signing & Capabilities settings.

Debug builds add **Open AX Inspector** to the menu-bar menu. Open the inspector while the target app
is frontmost, capture its AX hierarchy, then save a JSON fixture. Snapshots are written to:

```text
~/Library/Logs/OmniVim/Snapshots/
```

Run the HintEngine and fixture tests with either Xcode (`Command-U`) or:

```sh
./scripts/test.sh
```

The fixture-driven tests cover prefix-free hint codes, visibility clipping, hit-test rejection,
deterministic marker layout and AX snapshot decoding.

## Source layout

- `App`: application lifecycle and top-level coordination.
- `Vim`: Vim mode engine, command execution, focused editing sessions and mode presentation.
  Text-buffer components will live here as they are introduced.
- `Input`: global key monitoring and synthesized keyboard/mouse input.
- `Accessibility`: shared AX scanning and low-level AX operations.
- `Activation`: target activation policy and fallback sequencing.
- `Hints`: pure hint code, visibility, deduplication and layout engines.
- `UI`: hint overlay panels and markers.
- `Inspector`: AX inspector and snapshot recording.
- `Diagnostics`: diagnostic logging.

The coordinator owns the interaction flow. UI components report target selection but do not
activate other applications directly; activation is isolated behind `ElementActivator`.

Build the same Xcode app used during development and copy it to the repository root:

```sh
./scripts/build-app.sh
```

## Manual package build

```sh
swift run
```

The Swift package remains available as a lightweight compiler/test harness. The Xcode app target is
the canonical development and debugging surface.

## Thanks

OmniVim is informed by the work and ideas in these projects:

- [VimMode.spoon](https://github.com/dbalatero/VimMode.spoon) for demonstrating system-wide Vim
  motions and operators on macOS, including Accessibility-backed and keyboard-fallback strategies.
- [CodeMirror Vim](https://github.com/replit/codemirror-vim) for its composable Vim command,
  operator, motion and key-mapping model.
- [VSCodeVim](https://github.com/VSCodeVim/Vim) for its extensive Vim emulation behavior and
  operator-pending mode semantics.
- [Vimac](https://github.com/nchudleigh/vimac) for its native Swift implementation of macOS
  Accessibility-driven hints and keyboard navigation.

Thank you to their maintainers and contributors for making their work available to study and learn
from. OmniVim does not imply endorsement by or affiliation with these projects.
