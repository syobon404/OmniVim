#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_file="$repository_root/Integrations/fish/conf.d/omnivim.fish"
target_directory="${XDG_CONFIG_HOME:-$HOME/.config}/fish/conf.d"
target_file="$target_directory/omnivim.fish"

mkdir -p "$target_directory"

if [ ! -w "$target_directory" ]; then
    echo "Fish conf.d is read-only (it may be managed by Home Manager): $target_directory" >&2
    echo "Add Integrations/fish/conf.d/omnivim.fish to your declarative fish configuration instead." >&2
    exit 1
fi

if [ -e "$target_file" ] && [ ! -L "$target_file" ]; then
    echo "Refusing to replace existing file: $target_file" >&2
    exit 1
fi

ln -sfn "$source_file" "$target_file"
echo "Installed OmniVim fish companion at $target_file"
echo "Open a new fish session to activate it."
