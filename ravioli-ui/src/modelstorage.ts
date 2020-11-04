import localForage from "localforage";
import type { SqlJs } from 'sql.js/module';

export async function getLanguageModel(SQL, lang: string) {
  let key = `model-${lang}`;
  let stored = await localForage.getItem(key);
  if(stored == null) {
  let typedArray = new Uint8Array(await (await fetch(`/${lang}.sqlite`)).arrayBuffer())
    let db = await new SQL.Database(typedArray);
    localForage.setItem(key, typedArray); // unawaited
    return db;
  } else {
    return await new SQL.Database(stored);
  }
}

export async function saveModel(SQL, db: SqlJs.Database, lang:string): Promise<SqlJs.Database> {
  let key = `model-${lang}`;
  // export closes db and frees all prepared statements...
  await localForage.setItem(key, db.export())

  // therefore return new db instance
  return await new SQL.Database(await localForage.getItem(key));
}
