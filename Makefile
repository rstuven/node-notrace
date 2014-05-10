SRC = src
LIB = lib
BIN = bin
DOC = doc

all: clean js bin

js:
	@echo "coffee => js"
	@mkdir -p $(LIB)
	@coffee -co \
		$(LIB) \
		$(SRC)/*.coffee

bin:
	@mkdir -p $(BIN)
	@echo '#!/usr/bin/env node' | cat - $(LIB)/cli.js > /tmp/out && mv -f /tmp/out $(BIN)/notrace
	@rm $(LIB)/cli.js
	@chmod +x $(BIN)/notrace

clean:
	@rm -rf $(LIB)
	@rm -rf $(BIN)

test: all
	@mocha -R spec --compilers coffee:coffee-script/register

doc: all
	@echo "js => doc"
	@codex build -i $(DOC) -o ../node-notrace-doc
