# Ravioli

# Build requirements
`perl` `pv` `translate-shell` `yarn` `sponge` `unzip` `hexdump` `ar`
`cargo`

```
python3 -m venv .venv
source .venv/bin/activate

pip3 install cython wheel # required for colibri-core
pip3 install -r requirements.txt

# sqlite extension functions
gcc -g -fPIC -shared extension-functions.c -o extension-functions.so
```

# Translations
```
./create_tatoeba_translation_db.sh
./create_opensub_translation_db.sh [samples]
```

# Language model
```
./script.sh <langage as 3-letter code> [samples]
```

This generates the model and its translations in `out/$LANG_$SAMPLES/`.
It also copies everything into `ravioli-ui/public/languages`.
The files in this folder will be read at UI build time and reflects the language choices in the UI.

# Develop UI

```
yarn dev
```

# Deploy

```
yarn run build
firebase deploy
```
