# Catppuccin Mocha, with a persistent gitstatus daemon for Git information.
autoload -Uz add-zsh-hook
zmodload zsh/datetime

typeset -g _native_prompt_git='' _native_prompt_duration=''
typeset -g _native_prompt_character='' _native_prompt_context=''
typeset -gi _native_prompt_status=0
typeset -gi _native_prompt_git_enabled=0
typeset -gi _native_prompt_git_pending _native_prompt_git_generation _native_prompt_git_requested
typeset -g _native_prompt_git_directory

if [[ -o interactive && -t 0 ]]; then
	source "${ZSH_PLUGIN_DIR:-$HOME/.zsh-plugins}/gitstatus/gitstatus.plugin.zsh" '' &&
		gitstatus_start -s -1 -u -1 -c -1 -d -1 NATIVE_PROMPT &&
		_native_prompt_git_enabled=1
fi

function _native_prompt_git_render {
	_native_prompt_git=''
	[[ $VCS_STATUS_RESULT == ok-* ]] || return 0
	local branch=${VCS_STATUS_LOCAL_BRANCH:-@${VCS_STATUS_COMMIT[1,7]}}
	local -a indicators
	((VCS_STATUS_NUM_CONFLICTED)) && indicators+=("=$VCS_STATUS_NUM_CONFLICTED")
	((VCS_STATUS_NUM_STAGED)) && indicators+=("+$VCS_STATUS_NUM_STAGED")
	((VCS_STATUS_NUM_UNSTAGED)) && indicators+=("!$VCS_STATUS_NUM_UNSTAGED")
	((VCS_STATUS_NUM_UNTRACKED)) && indicators+=("?$VCS_STATUS_NUM_UNTRACKED")
	((VCS_STATUS_STASHES)) && indicators+=("*$VCS_STATUS_STASHES")
	((VCS_STATUS_COMMITS_AHEAD)) && indicators+=("⇡$VCS_STATUS_COMMITS_AHEAD")
	((VCS_STATUS_COMMITS_BEHIND)) && indicators+=("⇣$VCS_STATUS_COMMITS_BEHIND")

	# Branch names are data: escape prompt directives, and expand via a variable.
	_native_prompt_git=" on %F{#cba6f7} ${branch//\%/%%}%f"
	if (($#indicators)); then
		_native_prompt_git+=" %F{#f38ba8}[${(j: :)indicators}]%f"
	fi
}

function _native_prompt_git_receive {
	_native_prompt_git_pending=0
	# A command or directory change may have overtaken the outstanding request.
	if ((_native_prompt_git_requested != _native_prompt_git_generation)); then
		_native_prompt_git_query
		return
	fi
	_native_prompt_git_render
	zle && zle .reset-prompt
	return 0
}

function _native_prompt_git_query {
	((_native_prompt_git_enabled && ! _native_prompt_git_pending)) || return 0
	_native_prompt_git_requested=$_native_prompt_git_generation
	_native_prompt_git_pending=1
	# Warm results normally arrive immediately; slow scans finish asynchronously.
	if ! gitstatus_query -d "$PWD" -t 0.005 -c _native_prompt_git_receive NATIVE_PROMPT; then
		_native_prompt_git_pending=0
		_native_prompt_git=''
	elif [[ $VCS_STATUS_RESULT != tout ]]; then
		_native_prompt_git_receive
	fi
	return 0
}

function _native_prompt_git_update {
	((++_native_prompt_git_generation))
	if [[ $_native_prompt_git_directory != $PWD ]]; then
		_native_prompt_git_directory=$PWD
		_native_prompt_git=''
	fi
	_native_prompt_git_query
}

function _native_prompt_mode {
	local color='#a6e3a1' symbol='❯'
	((_native_prompt_status)) && color='#f38ba8'
	case ${ZVM_MODE:-${KEYMAP:-viins}} in
	n | vicmd)
		color='#bac2de'
		symbol='❮'
		;;
	v | V | visual | vivis | vivli)
		color='#f9e2af'
		symbol='❮'
		;;
	r | R)
		color='#cba6f7'
		symbol='❮'
		;;
	esac
	_native_prompt_character="%F{$color}$symbol%f"
}

function _native_prompt_preexec {
	_native_prompt_started=$EPOCHREALTIME
}

function _native_prompt_precmd {
	_native_prompt_status=$?
	local -i elapsed=0
	local duration
	_native_prompt_duration=''
	if [[ -n ${_native_prompt_started:-} ]]; then
		elapsed=$((EPOCHREALTIME - _native_prompt_started))
		unset _native_prompt_started
		if ((elapsed >= 2)); then
			if ((elapsed >= 3600)); then
				duration="$((elapsed / 3600))h $((elapsed % 3600 / 60))m"
			elif ((elapsed >= 60)); then
				duration="$((elapsed / 60))m $((elapsed % 60))s"
			else
				duration="${elapsed}s"
			fi
			_native_prompt_duration=" took %F{#f9e2af}$duration%f"
		fi
	fi
	_native_prompt_git_update
	_native_prompt_mode
}

# Allow switching from Starship in an existing shell as well as in new tabs.
add-zsh-hook -d precmd prompt_starship_precmd
add-zsh-hook -d preexec prompt_starship_preexec
add-zsh-hook precmd _native_prompt_precmd
add-zsh-hook preexec _native_prompt_preexec
typeset -gaU zvm_after_select_vi_mode_commands
zvm_after_select_vi_mode_commands+=(_native_prompt_mode)

[[ -n ${SSH_CONNECTION:-} ]] && _native_prompt_context='%F{#a6e3a1}%n@%m%f '
_native_prompt_mode
setopt promptsubst
PROMPT='${_native_prompt_context}%F{#7f849c}%3~%f${_native_prompt_git}${_native_prompt_duration}%(1j. %F{#89b4fa}✦ %j%f.)'$'\n''${_native_prompt_character} '
RPROMPT=''
PROMPT2='%F{#7f849c}…%f '
