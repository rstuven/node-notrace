exports.Quantizer = class Quantizer

    constructor: ->
        @counts = []
        @minIndex = Infinity
        @maxIndex = -Infinity
        @maxCount = 0

    add: do ->
        log2 = Math.log 2
        (value) ->
            index = @unsign value, 0, (x) -> 1+Math.floor(Math.log(x) / log2)
            @prepare index
            count = ++@counts[index - @minIndex]
            @maxCount = count if @maxCount < count

    unsign: (x, n, fn) ->
        if x is 0
            0
        else if x < 0
            -fn(-x-n)
        else
            fn(x-n)

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

    indexValue: (index) ->
        @unsign index, 1, ((x) -> Math.pow 2, x)

    count: (index) ->
        @counts[index - @minIndex]

