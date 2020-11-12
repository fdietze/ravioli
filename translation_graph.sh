#!/usr/bin/env bash
set -Eeuo pipefail # https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/#:~:text=set%20%2Du,is%20often%20highly%20desirable%20behavior.

# to visualize large graphs:
# sfdp -Goverlap=scale

ALLTRANSLATIONSFILE=$1
STARTSENTENCE=$2
LIMIT=${3-100}

q() { sqlite3 -column -init "" "$ALLTRANSLATIONSFILE" "$@"; }

SENTENCEID=$(q "SELECT sentenceid FROM sentences WHERE sentence = '$STARTSENTENCE' LIMIT 1")
echo "graph Sentences {"
echo "node [shape=box fontsize=20 margin=0 width=0 height=0]"

cat << EOF | sqlite3 -readonly -init "" "$ALLTRANSLATIONSFILE"
.bail on
.mode tabs

CREATE TEMPORARY TABLE sentence_nodes AS
WITH RECURSIVE nodes(id) AS (
    VALUES($SENTENCEID)
    UNION
    SELECT translationid FROM links JOIN nodes ON sentenceid = id
    LIMIT $LIMIT
    )
SELECT id FROM nodes;

-- nodes
SELECT id || ' [label="' || replace(trs.sentence, '"', '\\"') || '"]'
FROM sentence_nodes
JOIN sentences trs ON sentenceid = id;

-- induced subgraph
SELECT l.sentenceid || ' -- ' || l.translationid
FROM links l
WHERE
    l.sentenceid IN sentence_nodes AND l.translationid IN sentence_nodes
    AND l.sentenceid < l.translationid; -- remove backlinks


.mode csv
.headers on
.output sentences_nodes.csv
SELECT id as Id, trs.sentence as Label, trs.lang
FROM sentence_nodes
JOIN sentences trs ON sentenceid = id;

.output sentences_edges.csv
SELECT l.sentenceid as Source, l.translationid as Target
FROM links l
WHERE
    l.sentenceid IN sentence_nodes AND l.translationid IN sentence_nodes
    AND l.sentenceid < l.translationid; -- remove backlinks

EOF


echo "}"
