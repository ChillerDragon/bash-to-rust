#!/bin/bash

echo "[*] transpile tests"
for t in ./transpile_tests/*.sh
do
	./bash-to-rust.sh --bin a.out "$t"
	d="$(diff <(./a.out) <(bash "$t"))"
	if [ "$d" != "" ]
	then
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

