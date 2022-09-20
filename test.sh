#!/bin/bash

for t in ./test/*.sh
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

