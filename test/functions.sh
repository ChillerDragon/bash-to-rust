#!/bin/bash

function fun() {
	echo "this is fun"
}

function kevin_fun {
	echo "kevin home alone, parenthesis are gone :D"
}

posixfun() {
	echo "posix fun"
}

single_line_fun() { echo "foo"; }
function _single_line_fun() { echo "foo"; }

fun
posixfun
kevin_fun
single_line_fun
_single_line_fun

echo "function stringfun() { echo 'bar';fun; }"
# commentfun() { echo "comment";fun; }

