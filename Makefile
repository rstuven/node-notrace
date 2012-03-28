SRC = src
LIB = lib
BIN = bin
DOC = doc

all: clean js bin codex

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
	@rm -rf $(DOC)/out

test: all
	@mocha -R spec

codex:
	@echo "js => doc"
	@codex build -i doc
