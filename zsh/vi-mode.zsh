function zvm_config {
	ZVM_LINE_INIT_MODE=$ZVM_MODE_NORMAL

	# Match zvm_define_widget without its per-widget zle/declare subprocesses.
	zmodload zsh/parameter
	function zvm_define_widget {
		local widget=$1
		local func=${2:-$1}
		if [[ ${widgets[$widget]} == user:* ]]; then
			local rawfunc=${widgets[$widget]#user:}
			local wrapper="zvm_${widget}-wrapper"
			local called=false
			[[ ${functions[$func]} == *'$rawfunc'* ]] && called=true
			functions[$wrapper]="zvm_widget_wrapper ${(q)rawfunc} ${(q)func} $called \"\$@\""
			func=$wrapper
		fi
		zle -N "$widget" "$func"
	}
}
