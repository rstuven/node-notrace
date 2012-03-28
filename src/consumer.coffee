amqp = require 'amqp'
uuid = require 'uuid-v4.js'
colors = require 'colors'
rx = require 'rxjs'
{BSON} = require 'bson/lib/bson/bson'
{Delay} = require './timers'
{Timer} = require './timers'
{Pow2Quantizer, LinearQuantizer} = require './quantizer'
exchanges = require './exchanges'

# define custom aggregate functions
rx.Observable::quantize = () ->
    @aggregate new Pow2Quantizer, (q, v) ->
        q.add v
        q

rx.Observable::lquantize = (lb, ub, sv) ->
    @aggregate new LinearQuantizer(lb, ub, sv), (q, v) ->
        q.add v
        q

# constants
CONNECTION_END_WAIT = 30000 # time to wait before ending connection
RECONNECT_INTERVAL = 1000 # time between reconnection checks
REQUEST_ENABLE_INTERVAL = 5000 # time between probe enabling requests. see also PROBE_DISABLE_DELAY at Probe class.
REQUEST_SAMPLE_INTERVAL = 100 # time between probe sampling requests

###*
 * # Consumer
 *
 * This class enables specific probes, receives samples and provide facilities for aggregation of samples.
 *
 * @class Consumer
###
exports.Consumer = class Consumer

    ###*
     * @constructor
     * @param {Object} config (Optional) The configuration object.
    ###
    constructor: (@config = {}) ->
        @id = uuid()
        @reconnectTimer = new Timer
        @requestEnableTimer = new Timer
        @connectionEndDelay = new Delay

    ###*
     * # .sample()
     * Requests a single sample using probe key.
     * @param {String} probeKey The probe key with the format "provider.module.probe".
     * @param {Function} callback The callback function receives a 'subject' argument.
    ###
    sample: (probeKey, callback) ->
        @start probeKey, (subject) =>
            subject.subscribe (x) =>
                callback x
                @stop()

    ###*
     * # .start() [1]
     *
     * Starts a subscription to samples using probe key.
     *
     * A probe key has the format `provider.module.probe` and allows to use a `*` wildcard instead of each part. For example, the probe key `*.*.uptime` matches any probe named "uptime" of any provider in any module.
     *
     * The callback function receives a `subject` argument. Subject is an RxJS object that allows to subscribe to a stream of samples and processing them as they arrive using a powerful API.
     *
     * Examples:
     *
     * Receive a stream of samples.
     *
     *     consumer.start('*.*.myprobe', function (subject) {
     *       subject.subscribe(function (sample) {
     *         console.log(sample); // prints all arriving samples
     *       });
     *     });
     *
     * Calculate an average per second.
     *
     *     consumer.start('*.*.myprobe', function (subject) {
     *       subject
     *         .select(function (x) { return x.args[0]; })
     *         .windowWithTime(1000)
     *         .selectMany(function (win) { return win.average(); })
     *         .subscribe(function (x) { console.log(x); }); // prints a number every second
     *     });
     *
     * Calculate an average per second per module. Now this requires a little more involved use of bare RxJS. This can be simplified a lot using a `callbackConfig`.
     *
     *     consumer.start('*.*.myprobe', function (subject) {
     *       subject
     *         .windowWithTime(1000)
     *         .selectMany(function (win) {
     *           var agg = win
     *             .groupBy(function (x) { return x.module; })
     *             .selectMany(function (grp) {
     *               return grp.count().select(function (x) { return { module: grp.key, count: x }; }).zip(
     *                      grp.select(function (x) { return x.args[0]; }).average(),
     *                          function (f, r) { f.average = r; return f; });
     *             })
     *             .aggregate([], function (acc, x) { acc.push(x); return acc; });
     *           return agg;
     *         })
     *         .subscribe(function (x) { console.log(x); });
     *         // prints every second something like: [ {module:'a', average: 123}, {module:'b', average: 456} ]
     *     });
     *
     * @param {String} probeKey The probe key with the format "provider.module.probe".
     * @param {Function} callback The callback function receives a 'subject' argument.
    ###
    ###*
     * # .start() [2]
     *
     * Starts a subscription to samples using configuration objects.
     *
     * *callbackConfig* argument can have the following properties:
     *
     * - `mapbefore`: {String} Map expression before grouping and aggregating, evaluated right after `filterbefore`.
     * - `mapafter`: {String} Map expression after grouping and aggregating, evaluated right before the callback.
     * - `filterbefore`: {String} Filter using boolean expression at the beginning.
     * - `filterafter`: {String} Filter using boolean expression, evaluated right before `mapafter`.
     * - `aggregate`: {String} Aggregate function over expression.
     *  - Available aggregation functions are:
     *    - *count()*
     *    - *sum(expression)*
     *    - *min(expression)*
     *    - *max(expression)*
     *    - *average(expression)*
     *    - *quantize(expression)*
     *    - *lquantize(expression; lowerBound; upperBound; stepValue)*
     *  - Using `pair`, available aggregations are:
     *    - *elapsed_time()*
     *    - *delta(expression)*
     *    - *fraction(expression)*
     *    - *rate_per_millisecond(expression)*
     *    - *rate_per_second(expression)*
     *    - *average(expression1, expression2)*
     *    - *average_timer(expression1, expression2)*
     *    - *multi_timer(expression1, expression2)*
     *    - *multi_timer_inverse(expression1, expression2)*
     * - `aggregate2`: {String} Aggregate function to apply after `aggregate` with `pair`. Requires no `group` be specified.
     * - `group`: {String} Group expression.
     * - `window`: {String} Time window in the format `span[,shift]`. `span` is the length of each window. `[,shift]` is the optional interval between creation of consecutive windows.
     * - `pair`: {Boolean} Pair previous and current sample. Requires `aggregate` and no `group` be specified.
     * - `callback`: {Function} Callback function that receives result of processing.
     *
     * Expressions required above are strings containing JavaScript expressions. Sample properties are available as variables, unless a mapping or aggregating operation is applied.
     *
     * Examples:
     *
     * During 5 seconds, count how many samples per module there are:
     *
     *     consumer.start('*.*.random_walk', {
     *         aggregate: 'count()',
     *         group: 'module',
     *         callback: function(result) { console.log(result); }
     *     });
     *     consumer.stop({wait: 5000});
     *
     * During 1500 ms, every 500 ms, take a 1 second of samples, group them by module and average the first argument:
     *
     *     consumer.start('*.*.random_walk', {
     *         aggregate: 'average(args[0])',
     *         group: 'module',
     *         window: '1000,500',
     *         callback: function(result) { console.log(result); }
     *     });
     *     consumer.stop({wait: 1500});
     *
     * During 1 second, calculate the differences between a value and the next, then aggregate them all using quantize:
     *
     *     consumer.start('*.*.random_walk', {
     *         pair: true,
     *         aggregate: 'delta(args[0])',
     *         aggregate2: 'quantize',
     *         callback: function(result) { console.log(result); }
     *     });
     *     consumer.stop({wait: 1000});
     *
     * During 1 second, filter all values below 20, count per every 100 ms, filter counts above 0:
     *
     *     consumer.start({
     *       probeKey: '*.*.random',
     *       sampleInterval: 1 // request the matching probes to emit a sample every 1 millisecond.
     *     }, {
     *         filterbefore: 'args[1] < 20',
     *         window: '100',
     *         aggregate: 'count()',
     *         filterafter: 'count > 0',
     *         callback: function(sample) { console.log(sample); }
     *     });
     *     consumer.stop({wait: 1000});
     *
     * @param {Object} probeConfig The probe configuration object.
     * @param {Object} callbackConfig The callback configuration object.
    ###
    start: (config, callback) ->

        if @isBusy()
            throw new Error 'Consumer is busy. It must stop first.'

        if typeof callback is 'object'
            @start config, (subject) ->
                generateObservable(callback, subject)
                    .subscribe callback.callback
            return

        if typeof config is 'string'
            probeKey = config
        else
            probeKey = config.probeKey

        if config? and config.sampleInterval?
            @sampleInterval = config.sampleInterval
        else
            @sampleInterval = REQUEST_SAMPLE_INTERVAL

        # fill with asteriks where ommitted
        probeKey = probeKey.replace /^\./, '*.'
        probeKey = probeKey.replace /\.$/, '.*'
        probeKey = probeKey.replace /\.\./, '.*.'

        @probeKey = probeKey

        # subscribe
        @subject = new rx.Subject
        callback @subject

        # connect
        @connect()
        @reconnectTimer.start RECONNECT_INTERVAL, =>
            @connect() if not @connection?

    ###*
     * # .stop()
     *
     * Stops the current subscription to samples.
     *
     * It can be configured to wait a time before stopping (by default is immediate) and disconnect right away (by default, the connections remains open for some time, which is good for new subscriptions but a console application, for example, won't exit until the connection ends).
     *
     * Examples:
     *     consumer.stop(); // stop receiving samples, stay connected for the next subscription.
     *
     *     consumer.stop({
     *         wait: 5000, // stop after 5 seconds.
     *         disconnect: true
     *     });
     *
     * @param {Object} config.
    ###
    stop: (config = {}) ->
        if config.wait?
            wait = config.wait
            delete config.wait
            setTimeout =>
                @stop config
            , wait
            return

        @reconnectTimer.stop()
        @requestEnableTimer.stop()
        @request @probeKey, 'stop'
        if @subject?
            @subject.onCompleted()
            @subject = null
        if @queue?
            @queue.destroy()
            @queue = null
        @disconnect config.disconnect is true

    #
    # Publishes commands in the 'requests' exchange.
    # @param {String} probeKey The probe key with the format "provider.module.probe".
    # @param {String} request The request command.
    #
    request: (probeKey, request, args...) ->
        return if not @requests?
        message =
            request: request
            probeKey: probeKey
            consumerId: @id
            args: args
        message = BSON.serialize message
        try
            @requests.publish probeKey, message
        catch e
            @disconnect()

    #
    # Connects to server.
    # @private
    #
    connect: ->

        @connectionEndDelay.stop()

        if @connection?
            @open()
            return

        #console.log "Consumer of #{@probeKey} connecting..."

        host = @config.host or 'localhost'

        @connection = amqp.createConnection
            host: host

        @connection.on 'error', (err) =>
            console.error err
            @disconnect()

        @connection.on 'ready', =>
            @open()

    #
    # Open AMQP exchanges and subscribe to queues.
    # @private
    #
    open: ->
        exchanges.requests @connection, (exchange) =>
            return if not @connection?
            @requests = exchange

            # enable
            @request @probeKey, 'enable', @sampleInterval
            @requestEnableTimer.start REQUEST_ENABLE_INTERVAL, =>
                @request @probeKey, 'enable', @sampleInterval

            exchanges.samples @connection, (exchange) =>
                return if not @connection?
                @samples = exchange
                @connection.queue '', (queue) =>
                    return if not @connection?
                    @queue = queue
                    #console.log "queue.bind #{@samples.name}, #{@probeKey}.#{@id}"
                    queue.bind @samples.name, @probeKey + '.' + @id
                    queue.bind @samples.name, @probeKey + '.all'

                    #console.log 'queue subscribe'
                    # exclusive option is true so we have the same chance
                    # than other consumers of receiving a given sample.
                    queue.subscribe ack: false, exclusive: true
                    , (message) =>
                        message = BSON.deserialize message.data
                        #console.log 'queue:subscribe', message
                        @subject.onNext message if @subject?

                    # at least request a sample
                    @request @probeKey, 'sample'

    ###*
     * # .disconnect()
     *
     * Disconnects from server.
     *
     * @param {Boolean} immediate Specifies whether to disconnect immediately or to wait a few seconds 
    ###
    disconnect: (immediate = true) ->
        if @samples?
            @samples = null
        if @requests?
            @requests = null
        @connectionEndDelay.stop()
        if immediate
            if @connection?
                @connection.end()
                @connection = null
        else
            @connectionEndDelay.start CONNECTION_END_WAIT, =>
                if @connection?
                    @connection.end()
                    @connection = null

    ###*
     * # .isBusy()
     * Gets the busy state. When a subscription starts, we say the consumer is busy. When the subscription stops, the consumer is not busy.
     * @return {Boolean} The busy state.
    ###
    isBusy: ->
        @subject?


    ###*
     * # RxJS query generation.
     * Please, view source.
    ###
    #
    # @param {Object} config The configuration object
    #
    generateObservable = (config, subject) ->

        # create a function to evaluate a expression within sample context
        # in a way "this" is a reference to our "global" object.
        expression = (e) ->
            "function(_){return(function(){with(_){return #{highlight e};}}).call(global);}"

        # highlight code that comes from config
        highlight = (c) ->
            c.grey if c?

        code = ''

        # override global properties
        globalProps = (globalProp for globalProp of global when globalProp isnt 'console')
        code += "\nvar #{globalProps.join(',')};"

        # initialize our global object
        code += '\nglobal = {};'

        code += '\nvar s = subject;'
        if config.filterbefore?
            code += "s = s.where(#{expression config.filterbefore});"

        if config.mapbefore?
            code += "s = s.select(#{expression config.mapbefore});"

        if config.aggregate?
            aggMatches = config.aggregate.match ///
                ^
                \s*                 # ignore spaces
                ([^\(]+)            # function name
                \(
                    ([^;]*)         # first argument
                    (?:;            # separator is semicolon because arguments could be expressions with commas
                    (.*)            # more arguments
                    )?              #
                \)
                \s*                 # ignore spaces
                $
                ///
            if not aggMatches?
                throw new Error "Invalid aggregate format"
            aggFn = aggMatches[1]
            aggBy = aggMatches[2]
            aggBy2 = aggMatches[3]
            aggBy2 = aggBy2.replace /;/g, ',' if aggBy2?
            if aggBy? and aggBy.trim() isnt ''
                aggCode = ".select(#{expression aggBy})"
            else
                aggCode = ""
            aggCode += ".#{highlight aggFn}(#{highlight aggBy2})"
            aggName = aggFn
        else
            aggCode = ".take(1)"
            aggName = "sample"

        if config.group?
            groupCode = aggCode
            groupCode += ".select(function(_){return {key:grp.key, #{highlight aggName}:_};})"

            windowCode = ".groupBy(#{expression config.group})"
            windowCode += ".selectMany(function(grp){return grp#{groupCode};})"
            if config.filterafter?
                windowCode += ".where(#{expression config.filterafter})"
            windowCode += ".aggregate([], function(acc, _){ acc.push(_); return acc;})"
        else if config.pair
            windowCode = ".take(1)"
        else
            windowCode = aggCode
            if config.aggregate?
                windowCode += ".select(function(_){return {#{highlight aggName}:_};})"

        if config.window?
            code += "s = s.windowWithTime(#{highlight config.window});"
            code += "s = s.selectMany(function(win){return win#{windowCode};});"
        else if config.aggregate? and not config.pair
            code += "s = s#{windowCode};"

        if config.aggregate? and config.pair and not config.group?
            code += "s = s.zip(s.skip(1), function(p,c){return {prev:p, cur:c};});"
            code += "s = s.select(function(_){return pairAggregation('#{highlight aggFn}'"
            code += ",#{expression aggBy}"
            code += ",#{expression aggBy2}"
            code += ",_.prev, _.cur);});"
            if config.aggregate2?
                code += "s = s.#{highlight config.aggregate2}().select(function(_){return {\"#{highlight config.aggregate2} #{highlight aggFn}\":_};});"
            else
                code += "s = s.select(function(_){return {#{highlight aggFn}:_};});"

        if config.filterafter? and not config.group?
            code += "s = s.where(#{expression config.filterafter});"

        if config.mapafter?
            code += "s = s.select(#{expression config.mapafter});"

        code += "\nreturn s;"

        # add line breaks before some assignments
        code = code.replace /(s = s\.)/g, '\n$1'

        #console.log code

        # remove colors before compilation
        code = code.stripColors

        # compile code and execute it
        func = new Function 'subject', 'pairAggregation', code
        func.call {}, subject, pairAggregation

    ###*
     * # Pair aggregation.
     * Please, view source.
    ###
    # see http://msdn.microsoft.com/en-us/library/system.diagnostics.performancecountertype.aspx
    pairAggregation = (type, nFn, dFn, sampleOld, sampleNew) ->

        n0 = nFn sampleOld
        n1 = nFn sampleNew
        d0 = dFn sampleOld
        d1 = dFn sampleNew
        t0 = sampleOld.timestamp
        t1 = sampleNew.timestamp

        switch type
            when 'elapsed_time'
                (t1 - t0)
            when 'delta'
                (n1 - n0)
            when 'fraction'
                (n0 / d0)
            when 'average'
                (n1 - n0) / (d1 - d0)
            when 'rate_per_millisecond'
                (n1 - n0) / (t1 - t0)
            when 'rate_per_second'
                (n1 - n0) / (t1 - t0) * 1000
            when 'multi_timer'
                (n1 - n0) / (t1 - t0) * 100 / d1
            when 'average_timer'
                (n1 - n0) / (t1 - t0) / (d1 - d0)
            when 'multi_timer_inverse'
                (d1 - (n1 - n0) / (t1 - t0)) * 100
            when 'timer_100_ns_inverse'
                (1 - (n1 - n0) / (t1 - t0)) * 100

