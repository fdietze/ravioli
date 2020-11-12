import {shuffleArray, regExpEscape} from './utils'

export function modelPatternToRegExp(pattern: string, currentSentence: string): RegExp {
  let wildCardRegExp = new RegExp(/\{\*+\}/);
  let patternParts = pattern.split(" ").map((p) => {
    let isWildCard = wildCardRegExp.test(p);
    return isWildCard ? ".*" : regExpEscape(p);
  });
  let regex = new RegExp(patternParts.join("(\\s*)"));

  // only put spaces in the regex, if they are spaces in the real sentence.
  let matches = currentSentence.match(regex);

  const result = patternParts
    .map(
      (p, i) =>
        p + (i == patternParts.length - 1 ? "" : matches[1 + i])
    )
    .join("");

  // don't care about spaces before punctuation: TODO: Hey Mr. Dog.
  const punctuationAdjustedResult = result.replace(
    /\s*(\\\?|\\\.|!)$/,
    "\\s*$1"
  );
  return new RegExp(punctuationAdjustedResult);
}


export function getProposedWords(currentSentence: string): Array<String> {
  const separator = '#!#!#!'
  let words = currentSentence
    .replace(/([ \,\!\?'\-]+)/g, `$1${separator}`)
    .split(separator)
    .filter((w) => w != "");
  shuffleArray(words);
  return words;
}
