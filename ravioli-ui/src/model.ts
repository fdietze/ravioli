import {queryWithParams} from './db';
import type {SqlJs} from 'sql.js/module';


export function getSentence(db: SqlJs.Database, sentenceId: string): string {
  let res = db.exec(`SELECT sentence FROM sentences where sentenceid = ${sentenceId}`);
  return res[0].values[0][0].toString();
}

export function getSentencePatterns(db: SqlJs.Database, sentenceId: string): Array<string> {
  let res = db.exec(
    `SELECT p.pattern from reverseindex r JOIN patterns p ON r.pattern = p.pattern  WHERE sentenceid = ${sentenceId}`
  );
  return res[0].values.map((val) => val[0].toString());
}

export function nextSentenceId(db: SqlJs.Database): string {
  let PATTERNSCOREFN = "2*(1/p.coverage) + MIN(1/s.coverage)";
  let SENTENCESCOREFN = "(1/ss.coverage) + AVG(1/p.coverage*(p.proficiency-1)*(p.proficiency-1))"; // default proficiency is 2
  let query = `
        WITH
            next_patterns as (SELECT p.pattern FROM patterns p JOIN reverseindex r ON r.pattern = p.pattern JOIN sentences s ON s.sentenceid = r.sentenceid WHERE next_test <= (SELECT time FROM tick LIMIT 1) GROUP BY p.rank ORDER BY ${PATTERNSCOREFN} LIMIT 1),
            potential_sentences as ( SELECT sentenceid FROM reverseindex WHERE pattern IN next_patterns)
        SELECT
            s.sentenceid
        FROM
            potential_sentences as s
        JOIN reverseindex as r ON s.sentenceid = r.sentenceid
        LEFT OUTER JOIN patterns as p ON r.pattern = p.pattern
        JOIN sentences ss on ss.sentenceid = s.sentenceid
        GROUP BY r.sentenceid
        ORDER BY ${SENTENCESCOREFN} ASC
        LIMIT 1
        `;

  return db.exec(query)[0].values[0][0].toString();
}

export function nextTick(db: SqlJs.Database) {
  db.run(`UPDATE tick SET time = time + 1`);
}

export function learnedPattern(db: SqlJs.Database, pattern: string, correct: boolean) {
  let GAP = 4;
  if (correct) {
    queryWithParams(
      db,
      `UPDATE patterns SET proficiency = proficiency + 1, next_test = (SELECT time from tick LIMIT 1) + power(${GAP}, max(0, min(8, proficiency))) WHERE pattern = :pattern`,
      {":pattern": pattern}
    );
  } else {
    queryWithParams(
      db,
      `UPDATE patterns SET proficiency = proficiency - 1, next_test = (SELECT time from tick LIMIT 1) + ${GAP} WHERE pattern = :pattern`,
      {":pattern": pattern}
    );
  }
}
