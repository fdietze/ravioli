import {queryWithParams} from './db';
import type {SqlJs} from 'sql.js/module';
import {saveModel} from "./modelstorage";


export function getSentence(db: SqlJs.Database, sentenceId: string): string {
  console.log(`getSentence(${sentenceId})`);
  const res = db.exec(`SELECT sentence FROM sentences where sentenceid = ${sentenceId}`);
  return res[0].values[0][0].toString();
}

export function getSentencePatterns(db: SqlJs.Database, sentenceId: string): Array<{pattern: string, proficiency: number}> {
  console.log(`getSentencePatterns(${sentenceId})`);
  const res = db.exec(
    `SELECT p.pattern, p.proficiency from reverseindex r JOIN patterns p ON r.pattern = p.pattern  WHERE sentenceid = ${sentenceId}`
  );
  return res[0].values.map((val) => ({pattern: val[0].toString(), proficiency: val[1] as number}));
}

export function getNextSentenceId(db: SqlJs.Database): string {
  console.log(`getNextSentenceId()`);
  const SENTENCESCOREFN = '((1/s_coverage) + AVG(1/p_coverage*(p_proficiency+1)*(p_proficiency+1)))/matched_patterns' // default proficiency is 0
  const POTENTIAL_SENTENCE_LIMIT = 100;
  const PATTERN_LIMIT = 2;

  const SELECT_NEXT_PATTERNS = `SELECT p.pattern FROM patterns p WHERE next_test <= (SELECT time FROM tick LIMIT 1) ORDER BY p.score ASC LIMIT ${PATTERN_LIMIT}`
  const SELECT_POTENTIAL_SENTENCES = `SELECT r.sentenceid, COUNT(DISTINCT p.pattern) as matched_patterns FROM reverseindex r JOIN sentences s ON s.sentenceid = r.sentenceid JOIN patterns p ON r.pattern = p.pattern WHERE p.pattern IN next_patterns GROUP BY r.sentenceid ORDER BY s.coverage DESC LIMIT ${POTENTIAL_SENTENCE_LIMIT}`

  const query = `
WITH
    next_patterns as (${SELECT_NEXT_PATTERNS}),
    potential_sentences as (${SELECT_POTENTIAL_SENTENCES})
SELECT sentenceid FROM (
    SELECT
        s.sentenceid, ss.coverage as s_coverage, p.coverage as p_coverage, p.proficiency as p_proficiency
    FROM potential_sentences as s
    JOIN reverseindex as r ON s.sentenceid = r.sentenceid
    LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern
    JOIN sentences ss on ss.sentenceid = s.sentenceid
    GROUP BY r.sentenceid
    ORDER BY ${SENTENCESCOREFN} ASC
    LIMIT 1
)
        `;

  console.log(db.exec(SELECT_NEXT_PATTERNS)[0].values.map(row => row[0]));

  return db.exec(query)[0].values[0][0].toString();
}

export function setNextTick(db: SqlJs.Database) {
  db.run(`UPDATE tick SET time = time + 1`);
}


export async function saveExcerciseResult(
  SQL: SqlJs.SqlJsStatic,
  modelDb: SqlJs.Database,
  lang: string,
  matchedPatterns: Array<{pattern: string; matched: boolean}>,
  neededHints: boolean,
): Promise<SqlJs.Database> {
  for (const matchedPattern of matchedPatterns) {
    setLearnedPattern(
      modelDb,
      matchedPattern.pattern,
      matchedPattern.matched ? (neededHints ? 1 : 2) : -1
    );
  }
  setNextTick(modelDb);
  return await saveModel(SQL, modelDb, lang);
}


export function setLearnedPattern(db: SqlJs.Database, pattern: string, delta: number) {
  console.log("pattern proficiency: ", pattern, delta);
  const GAP = 4;
  if (delta > 0) {
    queryWithParams(
      db,
      `UPDATE patterns SET proficiency = proficiency + :delta, next_test = (SELECT time from tick LIMIT 1) + power(${GAP}, max(0, min(8, proficiency+2))) WHERE pattern = :pattern`,
      {":pattern": pattern, ":delta": delta}
    );
  } else if (delta < 0) {
    queryWithParams(
      db,
      `UPDATE patterns SET proficiency = proficiency + :delta, next_test = (SELECT time from tick LIMIT 1) + ${GAP} WHERE pattern = :pattern`,
      {":pattern": pattern, ":delta": delta}
    );
  }
}

export function getPatternOverview(db: SqlJs.Database): Array<{pattern: string, rank: number, proficiency: number}> {
  const res = db.exec(
    `select rank, pattern, proficiency from patterns where rank <= (select count(*) from patterns where proficiency > 0) - (select count(*) from patterns where proficiency < 0)`
  );

  if (res.length == 0) return [];
  return res[0].values.map((val) => ({rank: val[0] as number, pattern: val[1] as string, proficiency: val[2] as number}));
}
