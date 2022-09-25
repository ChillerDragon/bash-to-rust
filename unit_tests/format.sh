#!/bin/bash

source lib/strings.sh

function test_diff() {
	local expected="$1"
	local got="$2"
	if [ "$expected" != "$got" ]
	then
		echo ""
		echo "Error: test failed $(basename "$0"):$current_unit_test_name"
		echo ""
		echo "expected:"
		echo "$expected"
		echo ""
		echo "got:"
		echo "$got"
		exit 1
	fi
	printf '.'
}
function unit_test() {
	current_unit_test_name="$1"
}

unit_test interpolate

# shellcheck disable=SC2016
test_diff 'format!("foo {} {} {}", bar, baz, bang)' "$(interpolate_to_fmt '"foo $bar $baz $bang"')"
# shellcheck disable=SC2016
test_diff 'format!("hello {} {} {} {}", foo, bar, baz, world)' "$(_recurse_vars_in_fmt 'hello {} $foo $bar $baz' "world")"

