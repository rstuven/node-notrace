amqp = require 'amqp'
{EventEmitter} = require 'events'
{BSON} = require 'bson/lib/bson/bson'
{Probe} = require './probe'
{Timer} = require './timers'
exchanges = require './exchanges'

# constants
RECONNECT_INTERVAL = 5000 # time between reconnection checks

###*
 * # Provider
 *
 * This class is instantiatied by applications that need to be instrumented. A provider can be seen as the container of a category of probes.
 *
 * All providers defines a probe by default: `_probes`. This probe returns all probes defined in its provider.
 *
 * @class Provider
###
exports.Provider = class Provider extends EventEmitter

  ###*
   * Examples:
   *     // Probes can be defined using sync or async functions:
   *     // Not shown in this example, but this could be useful to call system stats tools.
   *     // (eg. mpstat, iostat, etc.)
   *     var p = new Provider({
   *       name: 'myprovider',
   *       probes: {
   *         // sync
   *         memory_heap_used: function () {
   *           return process.memoryUsage().heapUsed;
   *         },
   *         // async
   *         files_count: function (callback) {
   *           fs.readdir('/some/path', function (err, files) {
   *             if (err)
   *               callback(err);
   *             else
   *               // there could be multiple calls to callback in the same function.
   *               callback(null, files.length);
   *           });
   *         }
   *       }
   *     });
   * @constructor
   * @param {Object} config (Optional) The configuration object.
  ###
  constructor: (@config) ->
    if not @config? or not @config.name?
      throw new Error "Argument missing: config.name"

    @reconnectTimer = new Timer

    ###*
     * # .probes
     *
     * Gets defined probes.
     *
     * Example:
     *     var provider = new Provider({
     *         name: 'test',
     *         probes: {
     *             calls: ['number']
     *         }
     *     });
     *     provider.probes.calls.increment();
    ###
    @probes = {}
    if @config.probes?
      for name, args of @config.probes
        if typeof args is 'function'
          args =
            args: args
        args.name = name
        @addProbe args

    @addProbe
      name: '_probes'
      sampleThreshold: 0
      instant: true
      types: ['object']
      args: (cb) =>
        for name, probe of @probes
          cb null,
            name: name
            types: probe.types
            instant: probe.instant
            sampleThreshold: probe.sampleThreshold
        undefined

  ###*
   * # .addProbe()
   *
   * Adds a probe definition.
   *
   * Examples:
   *
   *     provider.addProbe('msg', 'string');
   *     provider.addProbe({
   *       name: 'uptime',
   *       args: function() { return process.uptime(); }
   *     });
   *
   * @param {String} name The name of the probe.
   * @param {params String} args The type of each argument.
  ###
  addProbe: (name, args...) ->
    probe = new Probe name, args...
    name = name.name if typeof name is 'object'
    @probes[name] = probe
    probe.on 'sample', (sample, consumerId) =>
      #console.log sample
      #console.log @samples?
      @emit 'sample', probe, sample, consumerId
      return if not @samples?
      message =
        provider: @config.name
        module: @module
        probe: probe.name
        timestamp: sample.timestamp
        hits: sample.hits
      message.args = sample.args if sample.args?
      message.error = sample.error.toString() if sample.error?
      #console.log message
      message = BSON.serialize message
      probeKey = "#{@config.name}.#{@module}.#{probe.name}"
      try
        if probe.instant
          #console.log '@samples.publish', probeKey+'.all'
          @samples.publish probeKey + '.all', message
        else if consumerId?
          #console.log '@samples.publish', probeKey+'.'+consumerId
          @samples.publish probeKey + '.' + consumerId, message
      catch e
        @disconnect()
    probe

  ###*
   * # instrument()
   *
   * Wraps a function so `func_enter` and `func_return` probes are updated before and after the function execution, respectively.
   *
   * If an object or a prototype is provided, all the functions down the hierarchy are instrumented.
   *
   * Examples:
   *
   *     // Instrument a single function
   *     obj.fn = provider.instrument(obj.fn, {name: 'fn', scope: obj});
   *
   *     // Instrument a prototype. All instances will be instrumented.
   *     provider.instrument(MyClass.prototype, {name: 'MyClass'});
   *
  ###
  instrument: (obj, options = {}) ->
    if not @probes.func_enter?
      @addProbe
        name: 'func_enter'
        instant: true
        sampleThreshold: 0
        types: ['object']
    if not @probes.func_return?
      @addProbe
        name: 'func_return'
        instant: true
        sampleThreshold: 0
        types: ['object']

    options.summaryDepth = options.summaryDepth or 5

    provider = this # current 'this' IS the provider.

    if typeof obj is 'function'
      return obj if obj.__notrace_instrumented
      wrapper = (args...) ->
        if options.callback
          callback = args[args.length - 1]
          if typeof callback is 'function'
            args[args.length - 1] = (cbargs...) ->
              elapsed = Date.now() - start
              if provider.probes.func_enter.updateable() # ask before calling 'summarize'
                provider.probes.func_enter.update options.name + ' <callback>',
                  callback: true
                  elapsed: elapsed
                  args: provider.summarize cbargs, options.summaryDepth
              result = callback cbargs...
              elapsed = Date.now() - start
              if provider.probes.func_return.updateable() # ask before calling 'summarize'
                provider.probes.func_return.update options.name + ' <callback>',
                  callback: true
                  elapsed: elapsed
                  result: provider.summarize result, options.summaryDepth
              result

        if provider.probes.func_enter.updateable() # ask before calling 'summarize'
          provider.probes.func_enter.update options.name,
            args: provider.summarize args, options.summaryDepth
        start = Date.now()
        scope = if options.scope? then options.scope else this # current 'this' IS NOT the provider but the object instance.
        result = obj.apply scope, args
        elapsed = Date.now() - start
        if provider.probes.func_return.updateable() # ask before calling 'summarize'
          provider.probes.func_return.update options.name,
            elapsed: elapsed
            result: provider.summarize result, options.summaryDepth
        result
      @markAsInstrumented wrapper
      return wrapper

    return if obj.__notrace_instrumented
    baseName = if options.name? then options.name + '.' else ''
    Object.keys(obj).forEach (key) =>
      prop = obj[key]
      if typeof prop is 'function'
        callback = options.callback is true or (options.callback instanceof Array and options.callback.indexOf(key) isnt -1)
        obj[key] = @instrument prop, name: baseName + key, callback: callback
      else if typeof prop is 'object' and prop isnt null
        @instrument prop
    @markAsInstrumented obj

  markAsInstrumented: (obj) ->
    Object.defineProperty obj, '__notrace_instrumented',
      value: true
      enumerable: false
      writable: false

  summarize: (value, depth) ->
    return '[stripped by provider]' if depth is 0
    if typeof value is 'function'
      '[function]'
    else if value instanceof Array
      value.map (x) => @summarize x, depth - 1
    else if typeof value is 'object'
      o = {}
      for k,v of value
        o[k] = @summarize v, depth - 1
      o
    else
      value

  ###*
   * # .update()
   *
   * Updates a probe.
   *
   * Also checks if the probe exists and creates it if not, which adds overhead, so use this method only for prototyping probes. Prefer declaring the probe on provider creation and access it through 'probes' property.
   *
   * Example:
   *     provider.update('cache_size', cache.size());
   *
   * @param {String} name The name of the probe.
   * @param {params} args The arguments of the probe.
  ###
  update: (name, args...) ->
    probe = @probes[name.name or name]
    probe = @addProbe name if not probe?
    probe.update args...

  ###*
   * # .increment()
   *
   * Increments a probe.
   *
   * Also checks if the probe exists and creates it if not, which adds overhead, so use this method only for prototyping probes. Prefer declaring the probe on provider creation and access it through 'probes' property.
   *
   * Example:
   *     provider.increment('rows', rows);
   *
   * @param {String} name The name of the probe.
   * @param {params} args The arguments of the probe increment.
  ###
  increment: (name, args...) ->
    probe = @probes[name.name or name]
    probe = @addProbe name if not probe?
    probe.increment args...

  ###*
   * # .sample()
   *
   * Updates a probe and emits a sample if possible.
   *
   * Also checks if the probe exists and creates it if not, which adds overhead, so use this method only for prototyping probes. Prefer declaring the probe on provider creation and access it through 'probes' property.
   *
   * Example:
   *     provider.sample('log', 'error', 'this is it!');
   *
   * @param {String} name The name of the probe.
   * @param {params} args The arguments of the probe.
  ###
  sample: (name, args...) ->
    probe = @probes[name.name or name]
    probe = @addProbe name if not probe?
    probe.instant = true
    probe.update args...

  ###*
   * # .start()
   *
   * Starts the provider. This internally means connect to server.
   *
   * Provider definitions can be reused across modules, so we must specify in what module we are.
   *
   * Example:
   *     provider.start('my_restful_api');
   *
   * @param {String} module The name of the module that is hosting the provider instance.
  ###
  start: (module) ->
    @module = module

    @connect()

    @reconnectTimer.start RECONNECT_INTERVAL, =>
      @connect() if not @connection?

  #
  # Connects to server.
  # @private
  #
  connect: ->
    #console.log "Provider #{@config.name}.#{@module} connecting..."
    host = @config.host or 'localhost'

    @connection = amqp.createConnection
      host: host

    @connection.on 'error', (err) =>
      console.log err
      @disconnect()

    @connection.on 'ready', =>
      exchanges.samples @connection, (exchange) =>
        return if not @connection?
        @samples = exchange

      exchanges.requests @connection, (exchange) =>
        return if not @connection?
        @requests = exchange
        @connection.queue '', (queue) =>
          # bind requests to this provider
          queue.bind exchange.name, ''

          # exclusive option is true so we have the same chance
          # than other providers of receiving a given request.
          queue.subscribe ack: false, exclusive: true, processRequestMessage

    processRequestMessage = (message) =>
      message = BSON.deserialize message.data

      return if not message.request?
      return if not message.probeKey?
      return if not message.consumerId?

      matches = /^([^\.]+)\.([^\.]+)\.([^\.]+)$/.exec message.probeKey

      return if not matches?
      return if ['*', @config.name].indexOf(matches[1]) is -1
      return if ['*', @module].indexOf(matches[2]) is -1

      probeName = matches[3]

      probes = if probeName is '*' then Object.keys @probes else [probeName]
      probes.forEach (probeName) =>
        probe = @probes[probeName]
        doRequest probe, message if probe?

    doRequest = (probe, message) =>
      probeKey = "#{@config.name}.#{@module}.#{probe.name}"
      #console.log "#{message.request} #{probeKey}"
      switch message.request
        when 'sample'
          probe.sample message.consumerId
        when 'enable'
          probe.enableForConsumer message.consumerId, message.args[0], probeKey
        when 'stop'
          probe.stop message.consumerId

  ###*
   * # .stop()
   *
   * Stops the provider.
   *
   * Example:
   *     provider.stop();
  ###
  stop: ->
    @reconnectTimer.stop()
    @disconnect()

  #
  # Disconnects from the server.
  # @private
  #
  disconnect: ->
    if @samples?
      @samples = null
    if @requests?
      @requests = null
    if @connection?
      @connection.end()
      @connection = null
