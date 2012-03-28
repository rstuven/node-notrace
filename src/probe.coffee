{EventEmitter} = require 'events'
uuid = require 'uuid-v4.js'
{Delay} = require './timers'
{Timer} = require './timers'

# constants
SAMPLE_THRESHOLD = 1000
PROBE_DISABLE_DELAY = 6000 # time to wait before disabling probes. see also REQUEST_ENABLE_INTERVAL at Consumer class.

###*
 * # Probe
 *
 * This class represents an instrumentation point.
 *
 * @class Probe
###
exports.Probe = class Probe extends EventEmitter

    constructor: (config, types...) ->
        @id = uuid()

        # multiple consumers support
        @consumerIds = [] # for instant sampling probes
        @consumerTimers = {} # for interval sampling probes

        @disableDelay = new Delay

        if typeof config is 'string'
            config =
                name: config
                types: types

        ###*
         * # .name
         * Gets the probe name
        ###
        if not config.name? or typeof config.name isnt 'string' or config.name is ''
            throw new Error "Argument is missing: 'name'"
        if config.name.match /[\.#*]/
            throw new Error 'Invalid character in name. The following are reserved: .#*'
        @name = config.name

        ###*
         * # .types
         * Gets the array of argument types.
        ###
        if (not config.types?) or (not config.types instanceof Array) or (config.types.length is 0)
            @types = ['number']
        else
            @types = config.types

        ###*
         * # .enabled
         * Gets the enabled status.
        ###
        @enabled = config.enabled is true # it's false by default

        ###*
         * # .instant
         * Gets the instant property value.
        ###
        @instant = config.instant is true # it's false by default

        ###*
         * # .sampleThreshold
         * Gets the sample threshold value.
        ###
        @sampleThreshold = if not config.sampleThreshold? then SAMPLE_THRESHOLD else config.sampleThreshold

        ###*
         * # .args
         * Gets the arguments.
        ###
        if config.args?
            if config.args instanceof Array
                @args = config.args
            else
                @args = [config.args]
            if @args.length is 1 and (typeof @args[0] is 'function')
                @args = @args[0]
        else
            @args = @types.map (type) -> if type is 'number' then 0 else ''

        ###*
         * # .hits
         * Gets the hits property value.
        ###
        @hits = 0

    ###*
     * # .update()
     *
     * Updates a probe.
     *
     * Example:
     *     probe.update(123, 'abc');
     *
     * @param {params} args The arguments of the probe.
    ###
    update: (args...) ->
        @args = args
        @hits++
        if @enabled and @instant
            @evaluate @args, (err, evaluated, timestamp) =>
                @sample null, null, evaluated, timestamp

    ###*
     * # .increment()
     *
     * Increments a probe.
     *
     * Example:
     *     probe.increment();
     *
     * @param {Number} offset (Optional) The increment offset. It can ben positive or negative. Default: +1.
     * @param {Number} index (Optional) The argument index. Default: 0.
    ###
    increment: (offset = 1, index = 0) ->
        arg = @args[index]
        if typeof arg isnt 'number'
            throw new Error "Argument of wrong type. args in index #{index} can not be incremented."
        @args[index] = arg + offset
        @hits++
        if @enabled and @instant
            @sample null, null, @args

    sample: (consumerId, callback, args, timestamp) ->
        now = Date.now()
        return unless @sampleThreshold is 0 or not @lastTimestamp? or (now - @lastTimestamp) >= @sampleThreshold
        @lastTimestamp = now

        go = (err, v, ts) =>
            sample =
                timestamp: ts or Date.now()
                hits: @hits
                args: v
                error: err
            consumerIds = if consumerId? then [consumerId] else @consumerIds
            @emit 'sample', sample, consumerIds
            callback null, sample, consumerIds if callback?

        if args?
            go null, args, timestamp
        else
            @evaluate @args, go

    evaluate: (args, callback) ->
        if typeof args is 'function'
            cb = (err, result, timestamp) ->
                if err
                    callback err
                    return

                if result instanceof Array
                    callback null, result, timestamp
                else
                    callback null, [result], timestamp

            try
                r = args cb
            catch e
                callback e
                return

            # if function returned a value, call callback immediately.
            # this assumes the function didn't use the callback.
            cb null, r if r?
        else
            callback null, args

    setEnabled: (enabled) ->
        @enabled = enabled
        if not enabled
            timer.stop() for consumerId, timer of @consumerTimers
            @consumerTimers = {}
            @consumerIds = []

    enableForConsumer: (consumerId, interval, probeKey) ->

        # register consumer
        if @instant
            newConsumerId = -1 is @consumerIds.indexOf consumerId
            if newConsumerId
                @consumerIds.push consumerId # yes, interval is ignored for instant sampling
        else
            newConsumerId =  not @consumerTimers.hasOwnProperty consumerId
            if newConsumerId
                @sampleByInterval consumerId, interval

        # enable with delayed disabling
        @enabled = true
        @disableDelay.start PROBE_DISABLE_DELAY, =>
            console.log 'disable', probeKey
            @setEnabled false

    sampleByInterval: (consumerId, interval) ->
        return if interval is 0
        timer = @consumerTimers[consumerId]
        if not timer?
            timer = new Timer
            @consumerTimers[consumerId] = timer
        timer.start interval, =>
            @sample consumerId

    stop: (consumerId) ->
        index = @consumerIds.indexOf consumerId
        if index isnt -1
            @consumerIds.splice index, 1

        timer = @consumerTimers[consumerId]
        if timer?
            timer.stop()
            delete @consumerTimers[consumerId]

