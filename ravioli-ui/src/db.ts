import type {SqlJs} from 'sql.js/module';

export async function getDbFromUrl(SQL: SqlJs.SqlJsStatic, url: string) {
  return new SQL.Database(new Uint8Array(await (await fetch(url)).arrayBuffer()));
}

declare var initSqlJs: SqlJs.InitSqlJsStatic; // make initSqlJs global var accessible
export async function initSQL() {
  const SQL = await initSqlJs({
    // Required to load the wasm binary asynchronously. Of course, you can host it wherever you want
    // You can omit locateFile completely when running in node
    locateFile: (file) => `https://sql.js.org/dist/${file}`,
  });

  return SQL;
}

let prepared_statements = {};
export function queryWithParams(db: SqlJs.Database, query:string, params:object) {
  try {
    return prepared_statements[query].getAsObject(params);
  } catch (err) {
    prepared_statements[query] = db.prepare(query);
    return prepared_statements[query].getAsObject(params);
  }
}

