#!/bin/zsh -f

zmodload zsh/zle zsh/parameter
ZVM_INIT_MODE=manual
source "${ZSH_PLUGIN_DIR:-$HOME/.zsh-plugins}/zsh-vi-mode/zsh-vi-mode.zsh" || exit 1
functions[_original_define_widget]=$functions[zvm_define_widget]
source "${0:A:h:h}/zsh/vi-mode.zsh" || exit 1
zvm_config
functions[_fast_define_widget]=$functions[zvm_define_widget]

function _test_raw {
	calls+=(raw)
	return 3
}
function _test_new {
	calls+=(new)
	return 0
}
function _test_with_raw {
	$rawfunc
	calls+=(new)
	return 0
}
function _test_widget {
	calls+=(default)
	return 0
}

typeset -A results
typeset -a calls
wrapper=zvm__test_widget-wrapper
for scenario in new default user aware builtin completion; do
	for implementation in original fast; do
		zle -D _test_widget 2>/dev/null
		unset "functions[$wrapper]"
		calls=()
		func=_test_new
		case $scenario in
		default) func='' ;;
		user) zle -N _test_widget _test_raw ;;
		aware)
			zle -N _test_widget _test_raw
			func=_test_with_raw
			;;
		builtin) zle -A self-insert _test_widget ;;
		completion) zle -C _test_widget complete-word _main_complete ;;
		esac

		_${implementation}_define_widget _test_widget $func || exit 1
		result="${widgets[_test_widget]}|${functions[$wrapper]-}"
		${widgets[_test_widget]#user:}
		result+="|$?|${(j:,:)calls}"
		results[$implementation]=$result
	done
	if [[ $results[original] != $results[fast] ]]; then
		print -u2 -r -- "FAIL: $scenario"
		print -u2 -r -- "original: $results[original]"
		print -u2 -r -- "fast: $results[fast]"
		exit 1
	fi
	print -r -- "PASS: $scenario"
done
