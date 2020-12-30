import {shuffleArray, regExpEscape} from './utils'

export function modelPatternToRegExp(rawPattern: string, currentSentence: string): RegExp {
  // remove punctuation from beginning and end of pattern
  let pattern = rawPattern.replace(/\s*[\.!?]$/, '');
  pattern = pattern.replace(/^¿\s*$/, '');

  let wildCardRegExp = new RegExp(/\{\*+\}/);
  let patternParts = pattern.split(" ").map((p) => {
    let isWildCard = wildCardRegExp.test(p);
    return isWildCard ? ".*" : regExpEscape(p);
  });
  let regex = new RegExp(patternParts.join("(\\s*)"));

  // only put spaces in the regex, if they are spaces in the real sentence.
  let matches = currentSentence.match(regex);

  let result = patternParts
    .map(
      (p, i) =>
        p + (i == patternParts.length - 1 ? "" : matches[1 + i])
    )
    .join("");

  // don't care about spaces before punctuation: TODO: Hey Mr. Dog.
  result = result.replace(
    /\s*(\\\?|\\\.|!)$/,
    "\\s*$1"
  );

  // don't care about spaces after comma
  result = result.replace(
    /,\s*/,
    ",\\s*"
  );
  return new RegExp(result);
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
