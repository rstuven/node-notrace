chai = require 'chai'
should = chai.should()
{Quantizer} = require '../src/quantizer'

describe 'Quantizer', ->

    describe '#constructor', ->

        it 'should initialize properties', ->
            q = new Quantizer
            q.minIndex.should.equal +Infinity
            q.maxIndex.should.equal -Infinity
            q.counts.should.eql []

    describe '#prepare', ->

        it 'should expand 0' ,->
            q = new Quantizer
            q.prepare 0
            q.minIndex.should.equal -1
            q.maxIndex.should.equal +1
            q.counts.should.eql [0,0,0]

        it 'should expand 1' ,->
            q = new Quantizer
            q.prepare 1
            q.minIndex.should.equal 0
            q.maxIndex.should.equal 2
            q.counts.should.eql [0,0,0]

        it 'should expand 0 twice' ,->
            q = new Quantizer
            q.prepare 0
            q.prepare 0
            q.minIndex.should.equal -1
            q.maxIndex.should.equal +1
            q.counts.should.eql [0,0,0]

        it 'should expand 0 then 1' ,->
            q = new Quantizer
            q.prepare 0
            q.prepare 1
            q.minIndex.should.equal -1
            q.maxIndex.should.equal +2
            q.counts.should.eql [0,0,0,0]

        it 'should expand +3' ,->
            q = new Quantizer
            q.prepare +3
            q.minIndex.should.equal +2
            q.maxIndex.should.equal +4
            q.counts.should.eql [0,0,0]

        it 'should expand -3' ,->
            q = new Quantizer
            q.prepare -3
            q.minIndex.should.equal -4
            q.maxIndex.should.equal -2
            q.counts.should.eql [0,0,0]

        it 'should expand +3 then -3' ,->
            q = new Quantizer
            q.prepare +3
            q.prepare -3
            q.minIndex.should.equal -4
            q.maxIndex.should.equal +4
            q.counts.should.eql [0,0,0,0,0,0,0,0,0]

        it 'should expand -3 then +3' ,->
            q = new Quantizer
            q.prepare -3
            q.prepare +3
            q.minIndex.should.equal -4
            q.maxIndex.should.equal +4
            q.counts.should.eql [0,0,0,0,0,0,0,0,0]

    describe '#add', ->

        it 'should count 2', ->
            q = new Quantizer
            q.add 123
            q.add 123
            q.counts.should.eql [0,2,0]

        it 'should count -1', ->
            q = new Quantizer
            q.add -1
            q.counts.should.eql [0,1,0]

        it 'should count 1 and 2', ->
            q = new Quantizer
            q.add 1
            q.add 2
            q.counts.should.eql [0,1,1,0]

        it 'should count', ->
            q = new Quantizer
            for i in [-7..7]
                q.add i
            q.minIndex.should.equal -4
            q.maxIndex.should.equal +4
            q.counts.should.eql [0,4,2,1,1,1,2,4,0]

        it 'should count 0..255', ->
            q = new Quantizer
            for i in [0..255]
                q.add i
            q.minIndex.should.equal -1
            q.maxIndex.should.equal 9
            q.counts.should.eql [0,1,1,2,4,8,16,32,64,128,0]

        it 'should count 1..255', ->
            q = new Quantizer
            for i in [1..255]
                q.add i
            q.minIndex.should.equal 0
            q.maxIndex.should.equal 9
            q.counts.should.eql [0,1,2,4,8,16,32,64,128,0]

    describe '#indexValue', ->

        it 'should return value', ->
            q = new Quantizer
            q.indexValue(0).should.equal 0
            q.indexValue(-1).should.equal -1
            q.indexValue(+1).should.equal +1
            q.indexValue(-3).should.equal -4
            q.indexValue(+3).should.equal +4
            q.indexValue(-5).should.equal -16
            q.indexValue(+5).should.equal +16

    describe '#count', ->

        it 'should return value', ->
            q = new Quantizer
            q.counts = [1,2,3,4,5]
            q.minIndex = -2
            q.maxIndex = +2
            q.count(-2).should.equal 1
            q.count(-1).should.equal 2
            q.count( 0).should.equal 3
            q.count(+1).should.equal 4
            q.count(+2).should.equal 5
            should.not.exist q.count(+3)
            should.not.exist q.count(-3)

