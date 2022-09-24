#!/bin/bash

arg_infile="$3"
arg_verbose=1

mkdir -p tmp

functions=()
str_scope='x'
function str_scope_get() {
	echo "${str_scope: -1}"
}
function str_scope_pop() {
	str_scope_get
	if [[ "${str_scope: -1}" == "x" ]]
	then
		return
	fi
	str_scope="${str_scope::-1}"
}
function str_scope_push() {
	str_scope+="$1"
}
function scope_is_str() {
	local s
	s="$(str_scope_get)"
	[[ "$s" == '"' ]] && return 0 # double quote
	[[ "$s" == "'" ]] && return 0 # single quote
	[[ "$s" == '$' ]] && return 0 # dollar string $''
	[[ "$s" == 'h' ]] && return 0 # HereDoc

	return 1
}
fn_scope='m'
function fn_scope_get() {
	echo "${fn_scope: -1}"
}
function fn_scope_pop() {
	fn_scope_get
	# m is main function
	# as of right now we can not leave that scope
	if [[ "${fn_scope: -1}" == "m" ]]
	then
		return
	fi
	fn_scope="${fn_scope::-1}"
}
function fn_scope_push() {
	fn_scope+="$1"
}
function scope_is_main_fn() {
	local s
	s="$(fn_scope_get)"
	[[ "$s" == 'm' ]] && return 0

	return 1
}
function scope_is_str_fn() {
	# returns true
	# if current scope
	# is a function that returns
	# a string
	# which is all functions that print to stdout in bash
	local s
	s="$(fn_scope_get)"
	[[ "$s" == 's' ]] && return 0 # bash echo, rust return String
	[[ "$s" == "i" ]] && return 0 # bash echo, rust return int
	[[ "$s" == 'r' ]] && return 0 # bash return no echo, rust return int

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
	val="$(bash_value_to_str_slice "$val")"
	if scope_is_str_fn
	then
		printf '__bash_stdout += %s;\n' "$val" >> tmp/main.rs
		[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
		printf '__bash_stdout += "\n";\n' >> tmp/main.rs
		[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	else
		printf 'println!("{}", %s);\n' "$val" >> tmp/main.rs
		[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	fi
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
function match_assign_to_subshell() {
	local stmt="$1"
	[[ "$stmt" =~ ([a-zA-Z_][a-zA-Z0-9_]*)\=\"?\$\((.*)\)\"? ]] || return 1

	local res
	local sub_code
	local fun
	local match
	res="${BASH_REMATCH[1]}"
	sub_code="${BASH_REMATCH[2]}"
	for fun in "${functions[@]}"
	do
		if [[ "$sub_code" == "$fun" ]]
		then
			match=1
			break
		fi
	done
	[[ "$match" == "1" ]] || return 1

	printf 'let %s = %s(false);\n' "$res" "$sub_code" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_fun_def() {
	local stmt="$1"
	local name
	local body=''
	if [[ "$stmt" =~ ^function\ ?([^ ]+)(.*) ]] && ! scope_is_str
	then
		name="${BASH_REMATCH[1]}"
		body="${BASH_REMATCH[2]}"
	elif [[ "$stmt" =~ ^([^ ]+)\(\)(.*) ]] && ! scope_is_str
	then
		name="${BASH_REMATCH[1]}"
		body="${BASH_REMATCH[2]}"
	else
		return 1
	fi
	[[ "$name" =~ \(\)$ ]] && name="${name::-2}"
	functions+=("$name")
	# always assume that the function prints to stdout
	# and that this string will be catched by a subshell
	# thus we mark it as "s" and return a String in rust
	fn_scope_push s
	printf "fn %s(print: bool) -> String {\n" "$name" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	echo 'let mut __bash_stdout = String::from("");' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	if [ "$body" != "" ]
	then
		[[ "$body" =~ [[:space:]]\{ ]] && body="$(echo "$body" | cut -d'{' -f2-)"
		parse_line "$body"
	fi
	return 0
}
function match_fun_def_end() {
	local stmt="$1"
	[[ "$stmt" == "}" ]] || return 1
	if ! scope_is_str_fn
	then
		return 1
	fi

	fn_scope_pop >/dev/null

	echo 'if print {' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	# TODO: should probably flush because print! does not
	echo '  print!("{}", __bash_stdout);' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	echo '}' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	echo 'strip_trailing_nl(&mut __bash_stdout);' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	echo '__bash_stdout' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	echo '}' >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_fun_call() {
	local stmt="$1"
	local fun
	local match=0
	local name
	for fun in "${functions[@]}"
	do
		if [[ "$stmt" == "$fun" ]]
		then
			name="$fun"
			match=1
			break
		fi
	done
	[[ "$match" == "1" ]] || return 1

	printf '%s(true);\n' "$name" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	return 0
}
function match_comment() {
	local stmt="$1"
	[[ "$stmt" =~ ^#(.*) ]] || scope_is_str || return 1

	printf '// %s\n' "${BASH_REMATCH[1]}" >> tmp/main.rs
	[[ "$arg_verbose" -gt 0 ]] && tail -n1 tmp/main.rs
	str_scope_push '#'
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
			if [[ "$(str_scope_get)" == "$char" ]]
			then
				str_scope_pop >/dev/null
			else
				str_scope_push "$char"
			fi
		fi
	done < <(echo -n "$line")
	echo "$stmt"
}

function parse_line() {
	local line="$1"
	if [ "$(str_scope_get)" == '#' ]
	then
		str_scope_pop > /dev/null
	fi
	if [ "$arg_verbose" -gt 0 ]
	then
		echo "bash: $line"
	fi
	match_comment "$line" && return
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
		match_fun_call "$stmt" && continue
		match_fun_def "$stmt" && continue
		match_fun_def_end "$stmt" && continue
		match_if_statement_if "$stmt" && continue
		match_if_statement_fi "$stmt" && continue
		match_echo_range "$stmt" && continue
		match_echo "$stmt" && continue
		match_arithmetic_expansion "$stmt" && continue
		match_assign_to_subshell "$stmt" && continue
		match_var_assign "$stmt" && continue
		match_str_concat "$stmt" && continue

		echo "$stmt" >> tmp/main.rs
	done < <(split_stmts "$line")
}

:>tmp/main.rs

cat << 'EOF' >> tmp/main.rs
fn strip_trailing_nl(input: &mut String) {
    let new_len = input
        .char_indices()
        .rev()
        .find(|(_, c)| !matches!(c, '\n' | '\r'))
        .map_or(0, |(i, _)| i + 1);
    if new_len != input.len() {
        input.truncate(new_len);
    }
}
EOF
echo "fn main() {" >> tmp/main.rs

while read -r line
do
	parse_line "$line"
done < <(awk NF "$arg_infile")

echo "}" >> tmp/main.rs

rustc -o a.out tmp/main.rs

