#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

SAMPLES=7000000

./script.sh fra $SAMPLES
./script.sh deu $SAMPLES
./script.sh ita $SAMPLES
./script.sh por $SAMPLES
./script.sh swe $SAMPLES
./script.sh spa $SAMPLES
