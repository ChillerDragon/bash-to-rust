#!/bin/bash

source lib/colors.sh

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
	printf '%b.%b' "$GREEN" "$RESET"
}
function unit_test() {
	current_unit_test_name="$1"
}
