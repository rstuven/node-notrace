[![Build Status](https://secure.travis-ci.org/rstuven/node-notrace.png?branch=master)](http://travis-ci.org/rstuven/node-notrace)
[![Coverage Status](https://coveralls.io/repos/rstuven/node-notrace/badge.svg)](https://coveralls.io/r/rstuven/node-notrace)
[![dependencies Status](https://david-dm.org/rstuven/node-notrace.svg)](https://david-dm.org/rstuven/node-notrace#info=dependencies)
[![devDependencies Status](https://david-dm.org/rstuven/node-notrace/dev-status.svg)](https://david-dm.org/rstuven/node-notrace#info=devDependencies)

## API documentation

http://rstuven.github.com/node-notrace/

## CLI

### Install

    npm install notrace --global

### Usage

    notrace list --help
    notrace sample --help

### Example

    node examples/provider.js &

    notrace sample --probe *.*.random --timeout 1000 --interval 200

    notrace sample --probe *.*.random --timeout 1000 --interval 1 --window 1000,500 --aggregate "quantize(args[1])"

![Sample quantize screenshot](doc/screenshot_quantize.png)
