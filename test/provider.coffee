sinon = require 'sinon'
chai = require 'chai'
chai.use require 'sinon-chai'
should = chai.should()
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
            should.exist p.probes.$probes

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

