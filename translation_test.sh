#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.
# shopt -s expand_aliases

SENTENCE='Comment ça se passe ?'
SOURCELANG='fra'
TARGETLANG='deu'

cat << EOF | sqlite3 -init "" "out/translations/translations.sqlite"
.mode column
.headers on

SELECT sentenceid, sentence
FROM sentences
WHERE
    sentence = '$SENTENCE' AND lang = '$SOURCELANG'
;
EOF

echo ""

cat << EOF | sqlite3 -init "" "out/translations/translations.sqlite"
.mode column
.headers on

SELECT s2.sentence as direct_translation
FROM sentences s1
JOIN links l ON l.sentenceid = s1.sentenceid
JOIN sentences s2 ON l.translationid = s2.sentenceid
WHERE
    s1.sentence = '$SENTENCE' AND s1.lang = '$SOURCELANG'
    AND s2.lang = '$TARGETLANG'
;
EOF



echo ""

# echo "A  -- X  -- O  -- X  -- A"
# echo "s1 -- s2 -- s3 -- s4 -- s5"
# echo "s1  -l1->  s2  -l2->  s3  -l3->  s4  -l4->  s5"

cat << EOF | sqlite3 -init "" "out/translations/translations.sqlite"
.mode column
.headers on

SELECT sentence as indirect_translation, COUNT(*) FROM
(SELECT s3.sentence
FROM sentences s1
JOIN links l1 ON l1.sentenceid = s1.sentenceid
JOIN links l2 ON l2.sentenceid = l1.translationid
JOIN sentences s3 ON s3.sentenceid = l2.translationid
JOIN links l3 ON l3.sentenceid = l2.translationid
JOIN links l4 ON l4.sentenceid = l3.translationid
WHERE
        s1.lang = '$SOURCELANG' AND s1.sentence = '$SENTENCE'
    AND s3.lang = '$TARGETLANG'
    AND l4.translationid = s1.sentenceid -- close cycle

    AND s1.sentenceid != l1.translationid
    AND l1.translationid != l2.translationid
    AND l2.translationid != l3.translationid
    )
GROUP BY sentence
ORDER BY COUNT(*) DESC
;
EOF
