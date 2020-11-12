import svelte from 'rollup-plugin-svelte';
import resolve from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import livereload from 'rollup-plugin-livereload';
import {terser} from 'rollup-plugin-terser';
import sveltePreprocess from 'svelte-preprocess';
import typescript from '@rollup/plugin-typescript';
import modify from 'rollup-plugin-modify';
import * as fs from 'fs';

const production = !process.env.ROLLUP_WATCH;

function serve() {
  let server;

  function toExit() {
    if (server) server.kill(0);
  }

  return {
    writeBundle() {
      if (server) return;
      server = require('child_process').spawn('npm', ['run', 'start', '--', '--dev'], {
        stdio: ['ignore', 'inherit', 'inherit'],
        shell: true
      });

      process.on('SIGTERM', toExit);
      process.on('exit', toExit);
    }
  };
}

export default {
  input: 'src/main.ts',
  output: {
    sourcemap: true,
    format: 'iife',
    name: 'app',
    file: 'public/build/bundle.js'
  },
  plugins: [
    svelte({
      // enable run-time checks when not in production
      dev: !production,
      // we'll extract any component CSS out into
      // a separate file - better for performance
      css: css => {
        css.write('bundle.css');
      },
      preprocess: sveltePreprocess({
        sourceMap: !production,
        postcss: true,
      }),
    }),

    // If you have external dependencies installed from
    // npm, you'll most likely need these plugins. In
    // some cases you'll need additional configuration -
    // consult the documentation for details:
    // https://github.com/rollup/plugins/tree/master/packages/commonjs
    resolve({
      browser: true,
      dedupe: ['svelte']
    }),
    commonjs(),
    typescript({
      sourceMap: !production,
      inlineSources: !production
    }),

    // In dev mode, call `npm run start` once
    // the bundle has been generated
    !production && serve(),

    // Watch the `public` directory and refresh the
    // browser on changes when not in production
    !production && livereload('public'),

    // If we're building for production (npm run build
    // instead of npm run dev), minify
    production && terser(),
    modify({
      'DEEPL_API_KEY': process.env.DEEPL_API_KEY,
      '"AVAILABLE_LANGUAGES"': JSON.stringify(available_languages()),
      // __buildDate__: () => new Date(),
      // __buildVersion: 15
    })
  ],
  watch: {
    clearScreen: false
  }
};

function available_languages() {
  const modelRegex = /([a-z]+)_model.sqlite/;
  const translatedRegex = /([a-z]+)_translated_([a-z]+).sqlite/;
  const files = fs.readdirSync("public/languages");
  // console.log(files);
  const languages = files.filter(f => modelRegex.test(f)).map(f => f.replace(modelRegex, '$1'));
  // console.log(languages);
  const translations = languages.map(l => {return {'lang': l, 'translations': files.filter(f => f.startsWith(l) && translatedRegex.test(f)).map(f => f.replace(translatedRegex, '$2'))}});
  console.log(translations)
  return translations;
}
