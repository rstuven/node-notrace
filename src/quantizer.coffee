###*
 * A frequency distribution of the values.
 * Increments the count in the highest bucket that is less than the value.
###
exports.Quantizer = class Quantizer

    constructor: ->
        @counts = []
        @minIndex = Infinity
        @maxIndex = -Infinity
        @maxCount = 0

    add: (value) ->
        index = @valueIndex value
        return if not index?
        @prepare index
        count = ++@counts[index - @minIndex]
        @maxCount = count if @maxCount < count

    prepare: (index) ->
        return if index < @maxIndex and index > @minIndex

        minIndex = Math.min index-1, @minIndex
        maxIndex = Math.max index+1, @maxIndex

        minUntil = if @minIndex is +Infinity then minIndex else @minIndex-1
        for i in [minIndex..minUntil] by 1
            @counts.unshift 0

        maxSince = if @maxIndex is -Infinity then maxIndex-1 else @maxIndex+1
        for i in [maxSince..maxIndex] by 1
            @counts.push 0

        @minIndex = minIndex
        @maxIndex = maxIndex

    count: (index) ->
        @counts[index - @minIndex]

    indexValue: (index) ->
        throw new Error 'Method not implemented.'

    valueIndex: (value) ->
        throw new Error 'Method not implemented.'

###*
 * A power-of-two frequency distribution of the values.
 * Increments the count in the highest power-of-two bucket that is less than the value.
###
exports.Pow2Quantizer = class Pow2Quantizer extends Quantizer

    indexValue: (index) ->
        @unsign index, 1, ((x) -> Math.pow 2, x)

    valueIndex: do ->
        log2 = Math.log 2
        (value) ->
            @unsign value, 0, (x) -> 1+Math.floor(Math.log(x) / log2)

    unsign: (x, n, fn) ->
        if x is 0
            0
        else if x < 0
            -fn(-x-n)
        else
            fn(x-n)

###*
 * A linear frequency distribution of values between the specified bounds.
 * Increments the count in the highest bucket that is less than the value.
###
exports.LinearQuantizer = class LinearQuantizer extends Quantizer

    constructor: (@lowerBound, @upperBound, @stepValue) ->
        throw new Error 'stepValue must be greater than 0.' if @stepValue <= 0
        throw new Error 'upperBound must be greater than lowerBound.' if @upperBound <= @lowerBound
        super()
        @prepare @valueIndex @lowerBound
        @prepare @valueIndex @upperBound

    indexValue: (index) ->
        @lowerBound + index * @stepValue

    valueIndex: (value) ->
        return null if value < @lowerBound
        return null if value > @upperBound
        Math.ceil((value - @lowerBound) / @stepValue)

