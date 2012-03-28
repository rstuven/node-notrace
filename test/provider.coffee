amqpmock = require 'amqp-mock'
sinon = require 'sinon'
require './sinon-predicate'
chai = require 'chai'
chai.use require 'sinon-chai'
should = chai.should()
{BSON} = require 'bson/lib/bson/bson'
{Provider} = require '..'

describe 'Provider', ->

    describe '#constructor', ->

        it 'should throw error on name missing', ->
            should.throw ->
                p = new Provider
            should.throw ->
                p = new Provider
                    probes: p1: -> 'a'

        it 'should initialize probes', ->
            p = new Provider name: 'p'
            should.exist p.probes
            should.exist p.probes._probes

        it 'should initialize probes config', ->
            p = new Provider
                name: 'p'
                probes:
                    p1:
                        types: ['string']
                    p2:
                        args: -> 123
                    p3: -> 123

            p.probes.p1.args.should.eql ['']
            p.probes.p2.args().should.eql 123
            p.probes.p3.args().should.eql 123

        #@TODO: Node.js probes provider
        it 'should support functions', (done) ->
            p = new Provider
                name: 'node'
                probes:
                    uptime:              -> process.uptime()
                    memory_heap_used:    -> process.memoryUsage().heapUsed
                    memory_heap_total:   -> process.memoryUsage().heapTotal
                    test_async:
                        types: ['string', 'string', 'string']
                        args: (cb) -> require('fs').readdir __dirname, cb
                    #test_async:           (cb) -> require('fs').readdir __dirname, (err, r) ->
                        #cb err, r.length

            setTimeout ->
                p.probes.test_async.sample 'c1', (err, s) ->
                    #console.log s
                    p.stop()
                    done()
            , 5

            p.start()


    describe '#addProbe', ->

        it 'should add a probe', ->
            p = new Provider name: 'p'
            p.addProbe 'p1', 'number', 'string'
            p.probes.p1.name.should.equal 'p1'
            p.probes.p1.types.should.eql ['number', 'string']

    describe '#update', ->

        beforeEach ->
            @p = new Provider name: 'p'

        afterEach ->
            Object.keys(@p.probes).length.should.equal 2

            spy = sinon.spy()
            @p.on 'sample', spy
            @p.probes.p1.sample 'c1'
            spy.should.have.been.calledOnce

        it 'should change args', ->
            po = @p.addProbe 'p1', 'string'
            @p.probes.p1.update 'val'
            @p.probes.p1.args.should.eql ['val']
            @p.probes.p1.id.should.equal po.id

        it 'should use an existent probe by name', ->
            po = @p.addProbe 'p1', 'number'
            @p.update 'p1', 123
            @p.probes.p1.args.should.eql [123]
            @p.probes.p1.id.should.equal po.id

        it 'should add a new probe by name if not exist', ->
            @p.update 'p1', 123
            @p.probes.p1.args.should.eql [123]

        it 'should use an existent probe by config', ->
            po = @p.addProbe 'p1', 'number'
            @p.update name: 'p1', 123
            @p.probes.p1.args.should.eql [123]
            @p.probes.p1.id.should.equal po.id

        it 'should add a new probe by config if not exist', ->
            @p.update name: 'p1', 123
            @p.probes.p1.args.should.eql [123]

    describe '#increment', ->

        beforeEach ->
            @p = new Provider name: 'p'

        afterEach ->
            Object.keys(@p.probes).length.should.equal 2

            spy = sinon.spy()
            @p.on 'sample', spy
            @p.probes.p1.sample 'c1'
            spy.should.have.been.calledOnce

        it 'should use an existent probe by name', ->
            po = @p.addProbe 'p1', 'number'
            @p.probes.p1.update 5
            @p.increment 'p1'
            @p.probes.p1.args.should.eql [6]
            @p.probes.p1.id.should.equal po.id

        it 'should add a new probe by name if not exist', ->
            @p.increment 'p1'
            @p.probes.p1.args.should.eql [1]

        it 'should use an existent probe by config', ->
            po = @p.addProbe 'p1', 'number'
            @p.probes.p1.update 5
            @p.increment name: 'p1'
            @p.probes.p1.args.should.eql [6]
            @p.probes.p1.id.should.equal po.id

        it 'should add a new probe by config if not exist', ->
            @p.increment name: 'p1'
            @p.probes.p1.args.should.eql [1]

    describe '#on.sample', ->

        it 'should receive sample event from probes', ->
            p = new Provider name: 'p'
            p.addProbe name: 'p1', types:['string'], enabled: true, instant: true
            p.addProbe name: 'p2', types:['string'], enabled: true, instant: true
            spy = sinon.spy()

            p.on 'sample', spy
            p.probes.p2.update 'a'
            p.probes.p1.update 'b'

            spy.should.have.been.calledTwice

            spy.getCall(0).args[0].should.eql p.probes.p2
            spy.getCall(0).args[1].args.should.eql ['a']

            spy.getCall(1).args[0].should.eql p.probes.p1
            spy.getCall(1).args[1].args.should.eql ['b']

        it 'should publish sample', (done) ->
            scope = amqpmock()
            p = new Provider name: 'p'
            p.addProbe name: 'p1', types:['string'], enabled: true, instant: true

            p.start 'm'

            p.probes.p1.enableForConsumer 'c1', 0, 'p.m.p1'

            setTimeout ->

                should.exist p.requests
                should.exist p.samples

                mock = sinon.mock p.samples
                mock.expects('publish').withArgs 'p.m.p1.all', sinon.predicate (actual) ->
                    actual = BSON.deserialize actual
                    actual.provider.should.equal 'p'
                    actual.module.should.equal 'm'
                    actual.probe.should.equal 'p1'
                    actual.args.should.eql ['b']
                    true

                p.probes.p1.update 'b'

                setTimeout ->
                    mock.verify()
                    scope.done()
                    done()
                , 1

            , 1

    describe '#start', ->

        it 'should connect', ->
            p = new Provider name: 'p'
            mock = sinon.mock p
            mock.expects('connect').once()

            p.start 'm'

            p.module.should.equal 'm'
            p.reconnectTimer.isStarted().should.be.true
            mock.verify()

    describe '#stop', ->

        it 'should disconnect', ->
            p = new Provider name: 'p'
            p.reconnectTimer.start 10000, ->
            mock = sinon.mock p
            mock.expects('disconnect').once()

            p.stop()

            p.reconnectTimer.isStarted().should.be.false
            mock.verify()

    describe '#connect', ->

        it 'should initialize connection', (done) ->
            scope = amqpmock()

            p = new Provider name: 'p'

            should.not.exist p.connection
            should.not.exist p.samples
            should.not.exist p.requests

            p.connect()

            setTimeout ->
                should.exist p.connection
                should.exist p.samples
                should.exist p.requests
                scope.done()
                done()
            , 1

        describe 'requests', ->

            beforeEach ->
                @p = new Provider name: 'p'
                @p.addProbe 'p1'
                @p.module = 'm'

                @mock = sinon.mock @p.probes.p1
                @scope = amqpmock().exchange('notrace-requests')

            it 'should sample', (done) ->

                @scope.publish '', BSON.serialize
                    request: 'sample'
                    probeKey: 'p.m.p1'
                    consumerId: 'c1'

                @mock.expects('sample').withExactArgs 'c1'

                @p.connect()

                setTimeout =>
                    @mock.verify()
                    @scope.done()
                    done()
                , 1

            it 'should enable', (done) ->

                @scope.publish '', BSON.serialize
                    request: 'enable'
                    probeKey: 'p.m.p1'
                    consumerId: 'c1'
                    args: [123]

                @mock.expects('enableForConsumer').withExactArgs 'c1', 123, 'p.m.p1'

                @p.connect()

                setTimeout =>
                    @mock.verify()
                    @scope.done()
                    done()
                , 1

            it 'should stop', (done) ->

                @scope.publish '', BSON.serialize
                    request: 'stop'
                    probeKey: 'p.m.p1'
                    consumerId: 'c1'

                @mock.expects('stop').withExactArgs 'c1'

                @p.connect()

                setTimeout =>
                    @mock.verify()
                    @scope.done()
                    done()
                , 1

    describe '#disconnect', ->

        it 'should end connection', ->
            p = new Provider name: 'p'
            p.samples = {}
            p.requests = {}
            p.connection = end: ->

            mock = sinon.mock p.connection
            mock.expects('end').once()

            p.disconnect()

            mock.verify()
            should.not.exist p.connection
            should.not.exist p.samples
            should.not.exist p.requests

