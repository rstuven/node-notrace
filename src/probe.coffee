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
     * Gets or sets the instant property value.
     *
     * If true, the probe will emit a sample right after a change (see `update` and `increment` methods).
     *
     * If false, consumers must request samples for a specific time interval. See `start` method of `Consumer`.
     *
     * Set this property only at initialization. DO NOT modify it after the probe starts operating.
     *
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

  updateable: ->
    @enabled and @instant

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
      @emit 'sample', sample, consumerId
      callback null, sample, consumerId if callback?

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

  enableForConsumer: (consumerId, interval, probeKey) ->
    @enabled = true

    if not @instant

      # register consumer
      if interval > 0 and not @consumerTimers[consumerId]?
        timer = new Timer
        @consumerTimers[consumerId] = timer
        timer.start interval, =>
          @sample consumerId

      # enable with delayed disabling
      @disableDelay.start PROBE_DISABLE_DELAY, =>
        #console.log 'disable', probeKey
        @enabled = false
        timer.stop() for consumerId, timer of @consumerTimers
        @consumerTimers = {}

  stop: (consumerId) ->
    if @instant
      @enabled = false
    else
      timer = @consumerTimers[consumerId]
      if timer?
        timer.stop()
        delete @consumerTimers[consumerId]
