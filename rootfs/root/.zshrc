typeset -U path
[[ -d $HOME/.local/bin ]] && path=($HOME/.local/bin $path)
[[ -d $HOME/.bun/bin ]] && path=($HOME/.bun/bin $path)

HISTFILE=$HOME/.zsh_history
[[ -d $HOME/workspace ]] && HISTFILE=$HOME/workspace/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS AUTO_CD

autoload -Uz compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

autoload -Uz vcs_info
zstyle ':vcs_info:git:*' formats ' %F{magenta}(%b)%f'
precmd() { vcs_info }
setopt PROMPT_SUBST
PROMPT='%F{green}%n@%m%f %F{cyan}%~%f${vcs_info_msg_0_} %# '

alias ls='ls --color=auto'
alias ll='ls -lh'
alias la='ls -lah'
alias grep='grep --color=auto'

bindkey -e
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[1~' beginning-of-line
bindkey '^[[4~' end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[5~' beginning-of-buffer-or-history
bindkey '^[[6~' end-of-buffer-or-history
