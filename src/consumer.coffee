amqp = require 'amqp'
uuid = require 'uuid-v4.js'
colors = require 'colors'
rx = require 'rxjs'
{BSON} = require 'bson/lib/bson/bson'
{Delay} = require './timers'
{Timer} = require './timers'
{Quantizer} = require './quantizer'
exchanges = require './exchanges'

# define custom aggregate functions
rx.Observable::quantize = () ->
    @aggregate new Quantizer, (q, v) ->
        q.add v
        q

# constants
CONNECTION_END_WAIT = 30000 # time to wait before ending connection
RECONNECT_INTERVAL = 1000 # time between reconnection checks
REQUEST_ENABLE_INTERVAL = 5000 # time between probe enabling requests. see also PROBE_DISABLE_DELAY at Probe class.
REQUEST_SAMPLE_INTERVAL = 100 # time between probe sampling requests

###*
 * Consumer enables specific probes, receives samples
 * and provide facilities for aggregation of samples.
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
     * Connects to AMQP server.
     * @private
    ###
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

    ###*
     * Open AMQP exchanges and subscribe to queues.
     * @private
    ###
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
                    #console.log 'queue bind ' + @probeKey
                    @queue = queue
                    queue.bind @samples.name, @probeKey + '.' + @id

                    #console.log 'queue subscribe'
                    # exclusive option is true so we have the same chance
                    # than other consumers of receiving a given sample.
                    queue.subscribe ack: false, exclusive: true
                    , (message) =>
                        message = BSON.deserialize message.data
                        #console.log message
                        @subject.onNext message if @subject?

                    # at least request a sample
                    @request @probeKey, 'sample'

    ###*
     * Disconnects from AMQP server.
     * @private
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
     * Requests a single sample using routing key.
     * @param {String} probeKey The probe routing key with the format "provider.module.probe".
     * @param {Function} callback The callback function receives a 'subject' argument.
    ###
    sample: (probeKey, callback) ->
        @start probeKey, (subject) =>
            subject.subscribe (x) =>
                callback x
                @stop()

    ###*
     * Gets the busy state.
     * @return {Boolean} The busy state.
    ###
    isBusy: ->
        @subject?

    ###*
     * Publishes commands in the 'requests' exchange.
     * @param {String} probeKey The probe routing key with the format "provider.module.probe".
     * @param {String} request The request command.
    ###
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

    ###*
     * Starts a subscription to samples using routing key.
     * @param {String} probeKey The probe routing key with the format "provider.module.probe".
     * @param {Function} callback The callback function receives a 'subject' argument.
    ###
    start: (config, callback) ->

        if @isBusy()
            throw new Error 'Consumer is busy. It must stop first.'

        if typeof callback is 'object'
            @start config, (subject) ->
                Consumer.generateObservable(callback, subject)
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
     * Stops the current subscription to samples.
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

    ###*
     * @param {Object} config The configuration object
    ###
    Consumer.generateObservable = (config, subject) ->

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
                    (.*)            # second argument
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
            if aggBy? and aggBy.trim() isnt ''
                aggCode = ".select(#{expression aggBy})"
            else
                aggCode = ""
            aggCode += ".#{highlight aggFn}()"
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
            code += "s = s.select(function(_){return calculate('#{highlight aggFn}'"
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
        func = new Function 'subject', 'calculate', code
        func.call {}, subject, calculate

    # see http://msdn.microsoft.com/en-us/library/system.diagnostics.performancecountertype.aspx
    calculate = (type, nFn, dFn, sampleOld, sampleNew) ->

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

