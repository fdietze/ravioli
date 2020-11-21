#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

SQLITEDB=$1

q() { sqlite3 "$SQLITEDB" --noheader "$@"; }

q "UPDATE tick SET time = 0"
q "UPDATE patterns SET proficiency = 0, next_test = 0;"
