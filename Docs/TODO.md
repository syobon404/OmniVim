# TODO

## Codex Desktop / Electron activation

- [ ] Make hint activation work reliably for Codex Desktop (`com.openai.codex`).

### Confirmed behavior

- OmniVim finds the correct target PID, frame and `AXButton`.
- The pointer moves to the correct on-screen position.
- `AXUIElementPerformAction(..., AXPress)` returns success (`0`), but Codex does not perform the action.
- A targeted `CGEvent.postToPid` mouse-down/mouse-up sequence is emitted successfully, but Codex still does not react.
- Event creation or AX success is not proof that Chromium handled the input.
- This is specific to the Codex/Chromium event bridge; do not assume that every Electron app behaves the same way.

### Failed approaches

- Treating a successful `AXPress` result as proof of activation.
- Posting an immediate global mouse-down/mouse-up pair.
- Posting mouse-down/mouse-up directly to the Codex PID, including an 80 ms hold interval.

### Next experiments

1. Set the target element's `AXFocused` attribute to `true`, then send Space; retry with Return.
2. If keyboard activation fails, send a complete global HID sequence: activate Codex, wait for focus, emit `mouseMoved`, wait, then emit delayed mouse-down/mouse-up through `.cghidEventTap`.
3. Add observable post-action verification instead of trusting AX/Quartz return values (window count, focused element, menu visibility, selected state, or app-specific AX-tree changes).
4. Keep Codex-specific workarounds scoped by bundle identifier to avoid double activation in applications where `AXPress` works.
5. If external macOS events remain ineffective, investigate whether Codex can expose a supported automation path through Electron `webContents.sendInputEvent`, IPC, or Chrome DevTools Protocol. OmniVim cannot access `webContents` directly without cooperation from Codex.

### Related resolved case

- System Settings sidebar rows are activated by setting `AXSelected=true`; they do not expose a usable `AXPress` action.
