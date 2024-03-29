import {setCORS} from "google-translate-api-browser";
import type {SqlJs} from "sql.js/module";
const translateGoogleAPI = setCORS("http://cors-anywhere.herokuapp.com/");


export function translateSentenceFromDb(db: SqlJs.Database, sentenceId: string): Array<{translation: string, probability: number, opacity: number}> {
  console.log(`translateSentenceFromDb(${sentenceId})`);
  const res = db.exec(`SELECT translation, probability, probability / (SELECT MAX(probability) FROM translations t WHERE t.sentenceid = ${sentenceId}) opacity FROM translations t WHERE t.sentenceid = ${sentenceId} ORDER BY probability DESC LIMIT 8`);
  if (res.length == 0) return [];
  return res[0].values.map(a => {return {translation: a[0].toString(), probability: a[1] as number, opacity: a[2] as number}});
}

export const translate = translateGoogle;

async function translateGoogle(
  text: string,
  source_lang: string,
  target_lang: string
): Promise<string> {
  if (text == "") return "";

  const res: any = await translateGoogleAPI(text, {from: source_lang, to: target_lang});
  console.log('Google Translate:', text, '->', res.text)
  return res.text;
}

async function translateDeepL(
  text: string,
  source_lang: string,
  target_lang: string
): Promise<string> {
  if (text == "") return "";

  // if(source_lang == 'fr') {
  //   // deepl workarounds
  //   text = text.replace(/\.$/, "");
  //   text = text.replace(/\s*([?!])$/, " $1");
  // }

  var data = new URLSearchParams();
  data.append("auth_key", "DEEPL_API_KEY");
  data.append("target_lang", target_lang);
  data.append("source_lang", source_lang);
  // data.append("split_sentences", "0");
  data.append("text", text);
  const response = await fetch("https://api.deepl.com/v2/translate", {
    method: "POST",
    body: data,
  });
  const json = await response.json();
  let result = json.translations[0].text;


  // if(target_lang == 'de')
  //   result = result.replace(/\s*([\.?!])$/, "$1");

  console.log('Google Translate:', text, '->', result)
  return result;
}
