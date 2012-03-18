exports.Timer = class Timer

    start: (interval, fn) ->
        @stop()
        @id = setInterval fn, interval

    stop: ->
        if @id?
            clearInterval @id
            @id = null

    isStarted: -> @id?

exports.Delay = class Delay

    start: (delay, fn) ->
        @stop()
        @id = setTimeout fn, delay

    stop: ->
        if @id?
            clearTimeout @id
            @id = null

    isStarted: -> @id?
