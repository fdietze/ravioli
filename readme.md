# Ravioli

# Build requirements
`perl` `pv` `translate-shell` `yarn` `sponge` `unzip` `hexdump` `ar`
`cargo`

```
python3 -m venv .venv
source .venv/bin/activate

pip3 install cython wheel # required for colibri-core
pip3 install -r requirements.txt

gcc -g -fPIC -shared extension-functions.c -o extension-functions.so
```
