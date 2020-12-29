import localForage from "localforage";
import type {SqlJs} from 'sql.js/module';

const modelKey = (lang: string) => `model-${lang}`;
const modelUrl = (lang: string) => `languages/${lang}_model.sqlite`;
const translationsKey = (lang: string, translationLang: string) => `model-${lang}-translated-${translationLang}`;
const translationsUrl = (lang: string, translationLang: string) => `languages/${lang}_translated_${translationLang}.sqlite`;

export function getLanguageModel(SQL: SqlJs.SqlJsStatic, lang: string): Promise<SqlJs.Database> {
  return loadCachedDb(SQL, modelKey(lang), modelUrl(lang));
}

export function getTranslations(SQL: SqlJs.SqlJsStatic, lang: string, translatedLang: string): Promise<SqlJs.Database> {
  return loadCachedDb(SQL, translationsKey(lang, translatedLang), translationsUrl(lang, translatedLang));
}


async function loadCachedDb(SQL: SqlJs.SqlJsStatic, key: string, url: string): Promise<SqlJs.Database> {
  let blob: Uint8Array = await localForage.getItem(key);
  if (blob == null) {
    console.log(`fetching ${url}`)
    blob = new Uint8Array(await (await fetch(url)).arrayBuffer());
    localForage.setItem(key, blob); // unawaited
  }

  return new SQL.Database(blob);
}


export async function saveModel(SQL: SqlJs.SqlJsStatic, db: SqlJs.Database, lang: string): Promise<SqlJs.Database> {
  // export closes db and frees all prepared statements...
  await localForage.setItem(modelKey(lang), db.export())

  // therefore return new db instance
  return new SQL.Database(await localForage.getItem(modelKey(lang)));
}
