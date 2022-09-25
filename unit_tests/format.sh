#!/bin/bash

source lib/unit_tests.sh
source lib/strings.sh


unit_test interpolate

# shellcheck disable=SC2016
test_diff 'format!("foo {} {} {}", bar, baz, bang)' "$(interpolate_to_fmt '"foo $bar $baz $bang"')"
# shellcheck disable=SC2016
test_diff 'format!("hello {} {} {} {}", foo, bar, baz, world)' "$(_recurse_vars_in_fmt 'hello {} $foo $bar $baz' "world")"

