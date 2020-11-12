#!/usr/bin/env python3

# https://en.wikipedia.org/wiki/ISO_3166-1
# https://github.com/konstantinstadler/country_converter#command-line-usage

from iso639 import languages
import sys

print(languages.get(part3=sys.argv[1]).part1)
