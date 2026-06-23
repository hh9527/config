#!/usr/bin/env bash
set -euo pipefail

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d%H%M%S)"
MANAGED_MARKER="managed by .config/shell/setup.sh"

install_stub() {
	local path="$1"
	local content="$2"

	if [ -e "$path" ] && ! grep -q "$MANAGED_MARKER" "$path"; then
		cp "$path" "$path.bak.$STAMP"
	fi

	printf "%s\n" "$content" > "$path"
}

install_link() {
	local source="$1"
	local target="$2"

	if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
		return
	fi

	if [ -e "$target" ] || [ -L "$target" ]; then
		mv "$target" "$target.bak.$STAMP"
	fi

	ln -s "$source" "$target"
}

mkdir -p "$CONFIG_HOME/bash" "$CONFIG_HOME/zsh"

install_stub "$HOME/.bashrc" "# $MANAGED_MARKER
case \$- in
	*i*) [ -f \"\$HOME/.config/bash/rc\" ] && source \"\$HOME/.config/bash/rc\" ;;
esac"

install_stub "$HOME/.bash_profile" "# $MANAGED_MARKER
[ -f \"\$HOME/.config/bash/profile\" ] && source \"\$HOME/.config/bash/profile\"
case \$- in
	*i*) [ -f \"\$HOME/.config/bash/rc\" ] && source \"\$HOME/.config/bash/rc\" ;;
esac"

install_stub "$HOME/.profile" "# $MANAGED_MARKER
[ -f \"\$HOME/.config/bash/profile\" ] && source \"\$HOME/.config/bash/profile\""

install_link "$CONFIG_HOME/zsh/.zshenv" "$HOME/.zshenv"
