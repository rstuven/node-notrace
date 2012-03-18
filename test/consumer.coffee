amqpmock = require 'amqp-mock'
amqp = require 'amqp'
sinon = require 'sinon'
require './sinon-predicate'
chai = require 'chai'
chai.use require 'sinon-chai'
should = chai.should()
{BSON} = require 'bson/lib/bson/bson'
{Consumer} = require '..'


describe 'Consumer', ->

    describe '#constructor', ->
        it 'should have an id', ->
            c = new Consumer
            should.exist c.id

    describe '#connect', ->

        it 'should initialize connection and open if disconnected', (done) ->
            scope = amqpmock()

            c = new Consumer
            mock = sinon.mock c
            mock.expects('open').once()

            should.not.exist c.connection

            c.connect()

            setTimeout ->
                should.exist c.connection
                mock.verify()
                scope.done()
                done()
            , 1

        it 'should open if already connected', (done) ->
            scope = amqpmock()

            c = new Consumer
            mock = sinon.mock c
            mock.expects('open').twice()

            c.connect()
            c.connect()

            setTimeout ->
                mock.verify()
                scope.done()
                done()
            , 1


        it 'should stop connection end delay', (done) ->
            scope = amqpmock()

            c = new Consumer
            sinon.stub c, 'open'
            mock = sinon.mock c.connectionEndDelay
            mock.expects('stop').once()

            c.connect()

            setTimeout ->
                mock.verify()
                scope.done()
                done()
            , 1

    describe '#open', ->

        it 'should initialize requests and samples if connected', (done) ->
            scope = amqpmock()

            c = new Consumer
            c.connection = amqp.createConnection()
            c.probeKey = 'probeKey'
            c.sampleInterval = 123

            sinon.stub c.requestEnableTimer, 'start'

            mock = sinon.mock c
            mock.expects('request').withArgs('probeKey', 'enable', 123)
            mock.expects('request').withArgs('probeKey', 'sample')

            should.not.exist c.requests
            should.not.exist c.samples

            c.open()

            setTimeout ->
                should.exist c.requests
                should.exist c.samples
                mock.verify()
                scope.done()
                done()
            , 1

        it 'should not initialize requests and samples if disconnected', (done) ->
            scope = amqpmock()

            c = new Consumer

            mock = sinon.mock c
            mock.expects('request').never()

            c.open()

            setTimeout ->
                should.not.exist c.requests
                should.not.exist c.samples
                mock.verify()
                scope.done()
                done()
            , 1

    describe '#disconnect', ->

        it 'should disconnect immediately', ->

            c = new Consumer
            c.samples = {}
            c.requests = {}
            c.connection = end: ->
            c.connectionEndDelay.start 100000, ->
            c.connectionEndDelay.isStarted().should.be.true

            mock = sinon.mock c.connection
            mock.expects('end').once()

            c.disconnect true

            mock.verify()
            should.not.exist c.samples
            should.not.exist c.requests
            should.not.exist c.connection
            c.connectionEndDelay.isStarted().should.be.false


        it 'should disconnect not immediately', ->

            c = new Consumer
            c.samples = {}
            c.requests = {}
            c.connection = end: ->
            c.connectionEndDelay.isStarted().should.be.false

            mock = sinon.mock c.connection
            mock.expects('end').never()

            c.disconnect false

            mock.verify()
            should.not.exist c.samples
            should.not.exist c.requests
            should.exist c.connection
            c.connectionEndDelay.isStarted().should.be.true

    describe '#sample', ->

        it 'should receive one sample and stop', (done) ->

            scope = amqpmock().exchange('notrace-samples')

            c = new Consumer

            scope.publish 'p.m.x.' + c.id, BSON.serialize
                provider: 'p'
                module: 'm'
                probe: 'x'
                timestamp: 123
                hits: 1
                args: ['ok']

            scope.publish 'p.m.x.' + c.id, BSON.serialize
                provider: 'p'
                module: 'm'
                probe: 'x'
                timestamp: 124
                hits: 2
                args: ['not ok']

            c.sample 'p.m.x', (x) ->
                should.exist x
                x.provider.should.equal 'p'
                x.module.should.equal 'm'
                x.probe.should.equal 'x'
                x.timestamp.should.equal 123
                x.args.should.eql ['ok']

            setTimeout ->
                scope.done()
                done()
            , 1


    describe '#start', ->

        it 'should receive all samples until stop', (done) ->

            scope = amqpmock().exchange('notrace-samples')

            c = new Consumer

            scope.publish 'p.m.x.' + c.id, BSON.serialize
                provider: 'p'
                module: 'm'
                probe: 'x'
                timestamp: 123
                hits: 1
                args: ['ok']

            scope.publish 'p.m.x.' + c.id, BSON.serialize
                provider: 'p'
                module: 'm'
                probe: 'x'
                timestamp: 124
                hits: 2
                args: ['ok']

            spy = sinon.spy()

            c.start 'p.m.x', (subject) ->
                subject.subscribe spy

            setTimeout ->
                spy.should.have.been.calledTwice
                spy.should.have.been.calledWith sinon.predicate (x) -> x.timestamp is 123
                spy.should.have.been.calledWith sinon.predicate (x) -> x.timestamp is 124
                scope.done()
                done()
            , 1


        it 'should throw an error if it is busy', ->

            scope = amqpmock()

            c = new Consumer

            c.isBusy().should.be.false

            c.start 'p.m.x', (subject) ->

            c.isBusy().should.be.true

            should.throw ->
                c.start 'p.m.y', (subject) ->

