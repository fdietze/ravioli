#!/usr/bin/env bash
set -e # exit when one command fails

CORPUS=$1

q() { sqlite3 $CORPUS/$CORPUS.sqlite --noheader "$@"; }

q "UPDATE tick SET time = 0"
q "UPDATE patterns SET proficiency = 2, next_test = 0;"
