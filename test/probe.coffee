sinon = require 'sinon'
chai = require 'chai'
chai.use require 'sinon-chai'
should = chai.should()
{Probe} = require '..'

describe 'Probe', ->

    describe '#constructor', ->

        it 'should initialize properties', ->
            p = new Probe 'probe name', 'number', 'string', 'number'
            p.name.should.equal 'probe name'
            p.enabled.should.be.false
            p.types.should.eql ['number', 'string', 'number']
            p.args.should.eql [0, '', 0]

        it 'should accept a function as argument', ->
            p = new Probe
                name: 'p'
                args: -> 123
            p.args.should.be.instanceOf Function
            p.args().should.eql 123

        it 'should throw error on missing name', ->
            should.throw ->
                p = new Probe
            should.throw ->
                p = new Probe {}

        it 'should throw error on name containing reserved chars', ->
            should.throw ->
                p = new Probe '.'
            should.throw ->
                p = new Probe '#'
            should.throw ->
                p = new Probe '*'
            should.not.throw ->
                p = new Probe '\'$!"%&/\\(){}[]=?'

    describe '#update', ->

        it 'should change if disabled', ->
            p = new Probe 'p', 'string'
            p.enabled = false
            p.update 'an argument'
            p.args.should.eql ['an argument']

        it 'should change a single argument', ->
            p = new Probe 'p', 'string'
            p.enabled = true
            p.update 'an argument'
            p.args.should.be.instanceOf Array
            p.args.should.eql ['an argument']

        it 'should change a tuple', ->
            p = new Probe 'p', 'string', 'string'
            p.enabled = true
            p.update 'a', 'b'
            p.args.should.be.instanceOf Array
            p.args.should.eql ['a', 'b']

        it 'should not throw error on set argument of wrong type (number)', ->
            p = new Probe 'p'

            # don't validate at this point. avoid overhead and failure.
            # let consumers discard invalid samples if they want.
            should.not.throw ->
                p.update 'x'

        it 'should not throw error on set argument of wrong type (string)', ->
            p = new Probe 'p', 'number', 'string'
            should.not.throw ->
                p.update 1, 2

    describe '#evaluate', ->

        it 'should accept an argument', (done) ->
            p = new Probe 'p'
            p.evaluate [123], (err, args) ->
                args.should.eql [123]
                done()

        it 'should accept a function as argument', (done) ->
            p = new Probe 'p'
            p.evaluate (-> 123), (err, args) ->
                args.should.eql [123]
                done()

    describe '#sample', ->

        it 'should return a sample on sync argument', (done) ->
            p = new Probe
                name: 'p'
                args: -> 123
            p.sample 'c1', (err, s, cids) ->
                should.exist s.args
                s.args.should.eql [123]
                cids.should.eql ['c1']
                done()

        it 'should return a sample on async argument', (done) ->
            p = new Probe
                name: 'p'
                args: (cb) ->
                    setTimeout (-> cb null, 123 ), 1
                    undefined
            setTimeout ->
                p.sample 'c1', (err, s, cids) ->
                    should.exist s.args
                    s.args.should.eql [123]
                    cids.should.eql ['c1']
                    done()
            , 2

        it 'should return a sample on async argument with explicit timestamp', (done) ->
            p = new Probe
                name: 'p'
                args: (cb) ->
                    setTimeout (-> cb null, 123, 999 ), 1
                    undefined
            setTimeout ->
                p.sample 'c1', (err, s, cids) ->
                    should.exist s.args
                    s.timestamp.should.equal 999
                    s.args.should.eql [123]
                    cids.should.eql ['c1']
                    done()
            , 2

        it 'should return multiple samples on async argument', (done) ->
            # use case: execute mpstat and listen stdout, parsing and returning each line.
            p = new Probe
                name: 'p'
                args: (cb) ->
                    setTimeout (-> cb null, 123 ), 1
                    setTimeout (-> cb null, 456 ), 2
                    undefined
            spy = sinon.spy()
            setTimeout ->
                p.sample 'c1', spy
            , 3
            setTimeout ->
                spy.should.have.been.calledTwice
                done()
            , 10

        it 'should return a timestamp', (done) ->
            p = new Probe 'p'
            p.sample 'c1', (err, s, cids) ->
                should.exist s.timestamp
                done()

        it 'should change the timestamp', (done) ->
            p = new Probe
                name: 'p'
                sampleThreshold: 0
            p.sample 'c1', (err, s1, cids1) ->
                ts = s1.timestamp
                setTimeout(->
                    p.sample 'c2', (err, s2, cids2) ->
                        s2.timestamp.should.not.equal ts
                        done()
                , 1)

        it 'should not emit event', (done) ->
            p = new Probe
                name: 'p'
            p.on 'sample', (sample) ->
                throw new Error "sample event emitted"
            p.update 123
            setTimeout done, 10

        it 'should emit event explicitly', (done) ->
            p = new Probe
                name: 'p'
                enabled: true
            p.on 'sample', (sample) ->
                sample.args.should.eql [123]
                done()
            p.update 123
            p.sample()

        it 'should emit event implicitly', (done) ->
            p = new Probe
                name: 'p'
                instant: true
                enabled: true
            p.on 'sample', (sample) ->
                sample.args.should.eql [123]
                done()
            p.update 123

        it 'should not emit below threshold', ->
            p = new Probe
                name: 'p'
                sampleThreshold: 1000

            count = 0
            p.on 'sample', (sample) ->
                count++
                if count is 2
                    throw new Error "sample event emitted"

            p.sample()
            p.sample()

        it 'should emit above threshold', (done) ->
            p = new Probe
                name: 'p'
                sampleThreshold: 5

            count = 0
            p.on 'sample', (sample) ->
                count++
                done() if count is 2

            p.sample()
            setTimeout (-> p.sample()), 10

        it 'should emit if threshold is 0', (done) ->
            p = new Probe
                name: 'p'
                sampleThreshold: 0

            count = 0
            p.on 'sample', (sample) ->
                count++
                done() if count is 2

            p.sample()
            p.sample()

    describe '#increment', ->

        it 'should add an offset in the first argument by default', ->
            p = new Probe 'p', 'number'
            p.increment 1
            p.args.should.eql [1]
            p.increment 2
            p.args.should.eql [3]

        it 'should add an offset by index', ->
            p = new Probe 'p', 'number', 'number'
            p.increment 1, 1
            p.args.should.eql [0, 1]
            p.increment 2, 1
            p.args.should.eql [0, 3]

        it 'should throw error on increment non number', ->
            p = new Probe 'p', 'string'
            should.throw ->
                p.increment 1

        it 'should throw error on outbound index', ->
            p = new Probe 'p', 'string'
            should.throw ->
                p.increment 1, 1

