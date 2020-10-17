#!/usr/bin/env bash

CORPUS=$1

cat << EOF | sqlite3 $CORPUS/$CORPUS.sqlite
.mode column
.headers on
.width 9 60 90

.load ./extension-functions

SELECT
    avg((1/p.coverage)*(1/p.coverage)*(1/p.coverage)) as score,
    s.sentence,
    group_concat(p.pattern || ': ' || p.rank, ', ') as patterns
FROM sentences as s
JOIN reverseindex as r ON s.sentenceid = r.sentenceid
LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern
GROUP BY r.sentenceid
ORDER BY score ASC
LIMIT 200
;


EOF

