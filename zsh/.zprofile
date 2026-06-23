# Zsh login configuration.
path_prepend() {
	[ -d "$1" ] || return
	case ":$PATH:" in
		*":$1:"*) ;;
		*) PATH="$1:$PATH" ;;
	esac
}

path_prepend "$HOME/bin"
path_prepend "$HOME/.local/bin"
export PATH

unfunction path_prepend

[ -f "$HOME/.config/shell/profile" ] && source "$HOME/.config/shell/profile"
