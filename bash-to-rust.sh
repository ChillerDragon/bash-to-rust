#!/bin/bash

arg_infile="$3"
arg_verbose=1

mkdir -p tmp

scope='x'
function scope_get() {
	echo "${scope: -1}"
}
function scope_pop() {
	scope_get
	if [[ "${scope: -1}" == "x" ]]
	then
		return
	fi
	scope="${scope::-1}"
}
function scope_push() {
	scope+="$1"
}
function scope_is_str() {
	local s
	s="$(scope_get)"
	[[ "$s" == '"' ]] && return 0 # double quote
	[[ "$s" == "'" ]] && return 0 # single quote
	[[ "$s" == '$' ]] && return 0 # dollar string $''
	[[ "$s" == 'h' ]] && return 0 # HereDoc

	return 1
}

function bash_value_to_rust() {
	local val="$1"
	# quoted var
	if [[ "$val" =~ ^\"\$(.*)\" ]]
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
		val="String::from($val)"
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
	if [[ "$val" =~ ^\"\$(.*)\" ]]
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
	elif [[ "$val" =~ ^\".*\" ]]
	then
		test
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
# this should be done better
# also accounting for scope
# and variables including each others name
# right now
# it will make foo mutable if barfoo is reassigned
# also rust can do shadowing so ditch a few mutes
function need_mutable() {
	local var="$1"
	local num_assigns
	num_assigns="$(grep -cE "$var\+?=" "$arg_infile")"
	if [[ "$num_assigns" -gt 1 ]]
	then
		return 0
	fi
	return 1
}

function match_echo() {
	local stmt="$1"
	[[ "$stmt" =~ echo\ (.*) ]] || return 1

	local val
	val="${BASH_REMATCH[1]}"
	val="$(bash_value_to_rust "$val")"
	printf 'println!("{}", %s);\n' "$val" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_echo_range() {
	local stmt="$1"
	[[ "$stmt" =~ echo\ \{([a-zA-Z0-9]+)\.\.([a-zA-Z0-9]+)\} ]] || return 1

	local val
	from="${BASH_REMATCH[1]}"
	to="${BASH_REMATCH[2]}"
	printf 'println!("{}", (%d..%d).map(|x|  x.to_string()).collect::<Vec<String>>().join(" "));\n' \
		"$from" \
		"$((to + 1))" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_var_assign() {
	local stmt="$1"
	[[ "$stmt" =~ ([a-zA-Z_][a-zA-Z0-9_]*)=(.*) ]] || return 1

	local var
	local val
	local mut=''
	var="${BASH_REMATCH[1]}"
	val="${BASH_REMATCH[2]}"
	val="$(bash_value_to_rust "$val")"
	if need_mutable "$var"
	then
		mut='mut '
	fi
	printf 'let %s%s = %s;\n' "$mut" "$var" "$val" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_str_concat() {
	local stmt="$1"
	[[ "$stmt" =~ ([a-zA-Z_][a-zA-Z0-9_]*)\+=(.*) ]] || return 1

	local var
	local val
	var="${BASH_REMATCH[1]}"
	val="${BASH_REMATCH[2]}"
	val="$(bash_value_to_str_slice "$val")"
	printf '%s = %s + %s;\n' "$var" "$var" "$val" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_if_statement_if() {
	local stmt="$1"
	[[ "$stmt" =~ if\ \[\ (.*)\ (-.+)\ (.*)\ \] ]] || return 1

	local lv
	local rv
	local op=''
	lv="${BASH_REMATCH[1]}" # todo: parse those into proper values supporting strings and quoted numbers etc
	op="${BASH_REMATCH[2]}"
	rv="${BASH_REMATCH[3]}"
	[[ "$op" == "-gt" ]] && op='>'
	[[ "$op" == "-lt" ]] && op='<'
	[[ "$op" == "-eq" ]] && op='=='
	[[ "$op" == "-ne" ]] && op='!='
	[[ "$op" != "" ]] || return 1

	printf 'if (%s %s %s) {\n' "$lv" "$op" "$rv" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_if_statement_fi() {
	local stmt="$1"
	[[ "$stmt" == "fi" ]] || return 1

	printf '}\n' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_arithmetic_expansion() {
	local stmt="$1"
	[[ "$stmt" =~ ([a-zA-Z_][a-zA-Z0-9_]*)\=\$\(\((.*)\)\) ]] || return 1

	local res
	local expression
	res="${BASH_REMATCH[1]}"
	expression="${BASH_REMATCH[2]}"

	# # shellcheck wants you do use no $ or quotes in there
	# but it is possible to do "$(("$num" + 1))"
	# but that is not supported YET

	printf '%s = %s;\n' "$res" "$expression" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_comment() {
	local stmt="$1"
	[[ "$stmt" =~ ^#(.*) ]] || scope_is_str || return 1

	printf '// %s\n' "${BASH_REMATCH[1]}" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	scope_push '#'
	return 0
}

function split_stmts() {
	local line="$1"
	local char
	local stmt=''
	local s
	while IFS= read -n1 -r char
	do
		if [[ "$char" == ";" ]] && ! scope_is_str
		then
			echo "$stmt"
			stmt=''
		else
			stmt+="$char"
		fi
		if [[ "$char" == "'" ]] || [[ "$char" == '"' ]]
		then
			if [[ "$(scope_get)" == "$char" ]]
			then
				scope_pop >/dev/null
			else
				scope_push "$char"
			fi
		fi
	done < <(echo -n "$line")
	echo "$stmt"
}

:>tmp/main.rs

echo "fn main() {" >> tmp/main.rs

while read -r line
do
	if [ "$(scope_get)" == '#' ]
	then
		scope_pop > /dev/null
	fi
	if [ "$arg_verbose" -gt 0 ]
	then
		echo "bash: $line"
	fi
	match_comment "$line" && continue
	while read -r stmt
	do
		# a context less "then" is a bash syntax error
		# otherwise its in the context of a if statement
		# rust does not need the then it uses the { after the condition
		# so just drop them all
		if [[ "$stmt" =~ ^then ]] && ! scope_is_str
		then
			stmt="${stmt:4}"
		fi
		[[ "$stmt" == "" ]] && continue

		if [ "$arg_verbose" -gt 0 ]
		then
			printf "        %s\t-> " "$stmt"
		fi
		match_if_statement_if "$stmt" && continue
		match_if_statement_fi "$stmt" && continue
		match_echo_range "$stmt" && continue
		match_echo "$stmt" && continue
		match_arithmetic_expansion "$stmt" && continue
		match_var_assign "$stmt" && continue
		match_str_concat "$stmt" && continue

		echo "$stmt" >> tmp/main.rs
	done < <(split_stmts "$line")
done < <(awk NF "$arg_infile")

echo "}" >> tmp/main.rs

rustc -o a.out tmp/main.rs

