# OmniVim shell companion for fish. F20 is reserved as the local bridge trigger.
set -g __omnivim_cache_dir "$HOME/Library/Caches/OmniVim"
set -g __omnivim_command_file "$__omnivim_cache_dir/terminal-command"

function __omnivim_dispatch
    test -f "$__omnivim_command_file"; or return

    read -l omnivim_command < "$__omnivim_command_file"
    command rm -f "$__omnivim_command_file"

    switch "$omnivim_command"
        case move-character-left
            commandline -f backward-char
        case move-character-right
            commandline -f forward-char
        case move-line-down
            commandline -f down-line
        case move-line-up
            commandline -f up-line
        case move-word-forward
            commandline -f forward-word
        case move-word-backward
            commandline -f backward-word
        case move-line-start
            commandline -f beginning-of-line
        case move-line-end
            commandline -f end-of-line
        case delete-character-left
            commandline -f backward-delete-char
        case delete-character-right
            commandline -f delete-char
        case delete-word-forward
            commandline -f kill-word
        case delete-word-backward
            commandline -f backward-kill-word
        case delete-line-start
            commandline -f backward-kill-line
        case delete-line-end
            commandline -f kill-line
        case delete-whole-line
            commandline -f kill-whole-line
        case '*'
            return
    end

    commandline -f repaint
end

if status is-interactive
    command mkdir -p "$__omnivim_cache_dir"
    command touch "$__omnivim_cache_dir/fish-companion-ready"
    for omnivim_keymap in default insert visual
        # Kitty encodes the physical F20 key with its CSI-u functional key code.
        bind -M $omnivim_keymap \e\[57383u __omnivim_dispatch
        # Keep the traditional terminfo kf20 sequence for other terminals.
        bind -M $omnivim_keymap \e\[19\;2~ __omnivim_dispatch
    end
end
