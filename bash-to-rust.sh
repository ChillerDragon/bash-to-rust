#!/bin/bash

arg_infile="$3"

mkdir -p tmp

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

function match_echo() {
	[[ "$line" =~ echo\ (.*) ]] || return 1

	local val
	val="${BASH_REMATCH[1]}"
	val="$(bash_value_to_rust "$val")"
	printf 'println!("{}", %s);\n' "$val" >> tmp/main.rs
	return 0
}
function match_var_assign() {
	[[ "$line" =~ ([a-zA-Z_][a-zA-Z0-9_]*)=(.*) ]] || return 1

	local var
	local val
	var="${BASH_REMATCH[1]}"
	val="${BASH_REMATCH[2]}"
	val="$(bash_value_to_rust "$val")"
	printf 'let %s = %s;\n' "$var" "$val" >> tmp/main.rs
	return 0
}
function match_comment() {
	[[ "$line" =~ ^#(.*) ]] || return 1

	printf '// %s' "${BASH_REMATCH[1]}" >> tmp/main.rs
	return 0
}

:>tmp/main.rs

echo "fn main() {" >> tmp/main.rs

while read -r line
do
	match_echo "$line" && continue
	match_var_assign "$line" && continue
	match_comment "$line" && continue

	echo "$line" >> tmp/main.rs
done < "$arg_infile"

echo "}" >> tmp/main.rs

rustc -o a.out tmp/main.rs

