#!/usr/bin/env python3

import sys
import stanza

lang = sys.argv[1]



stanza.download(sys.argv[1], processors='tokenize', logging_level='WARN')
nlp = stanza.Pipeline(lang=lang, processors='tokenize', logging_level='WARN')

for line in sys.stdin:
    doc = nlp(line.strip())
    for sentence in doc.sentences:
        print(sentence.text)




