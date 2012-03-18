sinon = require 'sinon'

sinon.predicate = (fn) ->
    new sinon.Predicate fn

class sinon.Predicate
    constructor: (@fn) ->
    eval: (actual) ->
        @fn actual

de = sinon.deepEqual
sinon.deepEqual = (expected, actual) ->
    if expected instanceof sinon.Predicate
        return expected.eval actual
    de.call null, expected, actual

