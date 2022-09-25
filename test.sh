#!/bin/bash

# pass -v for verbose output. Like this:
#
# ./test.sh -v

echo "[*] transpile tests"
for t in ./transpile_tests/*.sh
do
	./bash-to-rust.sh "$@" --bin a.out "$t"
	d="$(diff <(./a.out) <(bash "$t"))"
	if [ "$d" != "" ]
	then
		echo ""
		echo "Run this for for more info:"
		tput bold
		echo "  ./bash-to-rust.sh -vvv --bin a.out $t"
		tput sgr0
		echo ""
		echo "FAILED test $t diff:"
		echo "$d"
		exit 1
	else
		printf '.'
	fi
done

echo "[*] unit tests"
for t in ./unit_tests/*.sh
do
	$t || exit 1
done

