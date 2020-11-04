FROM proycon/lamachine

USER root
RUN DEBIAN_FRONTEND=noninteractive apt-get -y install sqlite3 libsqlite3-dev

USER lamachine
RUN pip3 install -U stanza
# RUN pip3 install -U spacy

