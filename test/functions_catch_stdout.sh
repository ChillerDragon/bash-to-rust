#!/bin/bash

function hello() {
	echo "hello"
	echo "world"
}

str="$(hello)"
echo "$str"

function trim_me() {
	echo ""
	echo ""
	echo ""
	echo "hello"
	echo ""
	echo ""
	echo "world"
	echo ""
	echo ""
	echo ""
}

str=$(trim_me)
echo "$str"

