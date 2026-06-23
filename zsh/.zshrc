# Zsh-only interactive configuration.
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=1000
SAVEHIST=2000
mkdir -p "${HISTFILE:h}" "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"

setopt append_history
setopt hist_ignore_dups
setopt hist_ignore_space
setopt share_history
setopt auto_cd
setopt interactive_comments

autoload -Uz compinit
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

[ -f "$HOME/.config/shell/rc" ] && source "$HOME/.config/shell/rc"
