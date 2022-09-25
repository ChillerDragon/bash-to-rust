#!/bin/bash

function _recurse_vars_in_fmt() {
	# do not call this directly
	# it is just a recursive helper
	#
	# give a unquoted format string and the filling vars
	# as two parameters
	# it will search if there is one more bash var
	# in the format string
	# if so it will call it self
	# with the new format string and parameter list
	#
	# if no further variables found it will return
	# the full rust format statement
	#
	# EXAMPLE
	#
	#   _recurse_vars_in_fmt "hello {} $var" "world"
	#
	#    -> "format!("hello {} {}", world, var)"

	local fmt_str="$1"
	local var_list="$2"
	if [[ "$fmt_str" =~ (.*)\$([a-zA-Z_][a-zA-Z0-9_]*)(.*) ]]
	then
		local str_left
		local str_right
		local var
		var="${BASH_REMATCH[2]}"
		str_left="${BASH_REMATCH[1]}"
		str_right="${BASH_REMATCH[3]}"

		# insert format placeholder
		printf -v fmt_str '%s{}%s' "$str_left" "$str_right"
		# append var to list
		var_list="$var, $var_list"

		_recurse_vars_in_fmt "$fmt_str" "$var_list"
	else
		printf 'format!("%s", %s)' "$fmt_str" "$var_list"
	fi
}
function interpolate_to_fmt() {
	# given a interpolated and quoted
	# bash string
	# it returns a rust format! macro
	#
	# if it could not find a proper quoted string
	# it prints nothing
	local str="$1"
	if [[ "$str" =~ ^\"(.*)\$([a-zA-Z_][a-zA-Z0-9_]*)(.*)\"$ ]]
	then
		local str_left
		local str_right
		local fmt_str
		local var
		var="${BASH_REMATCH[2]}"
		str_left="${BASH_REMATCH[1]}"
		str_right="${BASH_REMATCH[3]}"

		printf -v fmt_str '%s{}%s' "$str_left" "$str_right"

		_recurse_vars_in_fmt "$fmt_str" "$var"
	else
		echo ""
	fi
}
function bash_value_to_rust() {
	local val="$1"
	# quoted var
	if [[ "$val" =~ ^\"\$([a-zA-Z_][a-zA-Z0-9_])\"$ ]]
	then
		val="${BASH_REMATCH[1]}"
	# unquoted var
	elif [[ "$val" =~ ^\$([^\ ]*) ]]
	then
		val="${BASH_REMATCH[1]}"
	# number
	elif [[ "$val" =~ ^[0-9]+$ ]]
	then
		test
	# quoted string
	elif [[ "$val" =~ ^\".*\" ]]
	then
		local owned_string="String::from($val)"
		val="$(interpolate_to_fmt "$val")"
		# no interpolation found
		# fallback to String
		[[ "$val" == "" ]] && val="$owned_string"
	# unquoted string
	elif [[ "$val" =~ ^([^ ]+) ]]
	then
		val="String::from(\"${BASH_REMATCH[1]}\")"
	else
		echo "Failed to match value"
		exit 1
	fi
	echo "$val"
}
function bash_value_to_str_slice() {
	local val="$1"
	# quoted var
	# todo: define the pattern that matches bash variables once
	#       and use that pattern var instead hardcodet patterns
	if [[ "$val" =~ ^\"\$([a-zA-Z_][a-zA-Z0-9_])\"$ ]]
	then
		val="${BASH_REMATCH[1]}"
	# unquoted var
	elif [[ "$val" =~ ^\$([^\ ]*) ]]
	then
		val="${BASH_REMATCH[1]}"
	# number
	elif [[ "$val" =~ ^[0-9]+$ ]]
	then
		val="\"$val\""
	# quoted string
	elif [[ "$val" =~ ^\".*\"$ ]]
	then
		local oldval="$val"
		val="$(interpolate_to_fmt "$val")"
		# no interpolation found
		# fallback to quoted str slice
		[[ "$val" == "" ]] && val="$oldval"
	# unquoted string
	elif [[ "$val" =~ ^([^ ]+) ]]
	then
		val="\"${BASH_REMATCH[1]}\""
	else
		echo "Failed to match value"
		exit 1
	fi
	echo "$val"
}
