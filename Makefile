SRC = src
LIB = lib
BIN = bin

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
	@mocha -R spec


