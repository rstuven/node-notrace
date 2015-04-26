program = require 'commander'
util = require 'util'
colors = require 'colors'
{Consumer} = require '..'

version = JSON.parse(require('fs').readFileSync(__dirname + '/../package.json', 'utf8')).version

program
    .version(version)
    .usage('[command] [options]')
    .option('-C, --nocolor', 'Disable colors.')

Object.getPrototypeOf(program).commonOptions = ->
    this
        .option('-p, --probe [provider.module.probe]', 'Probe key. (default: *.*.*)', '*.*.*')
        .option('-R, --report [object|pretty]', 'Report format. (default: pretty)', 'pretty')

consumer = new Consumer

program
    .command('list')
    .description('List matching probes')
    .commonOptions()
    .action (command) ->
        matches = command.probe.match /^([^\.]*\.[^\.]*)\.?([^\.]*)$/
        matches = ['','*.*','*'] if not matches?
        query = matches[1] + '._probes'
        probeName = matches[2] or '*'
        console.log "Listing probes: #{matches[1]}.#{probeName}\n"
        consumer.start {probeKey: query, sampleInterval: 0}, (subject) ->
            subject
                .where((x) -> probeName is '*' or probeName is x.args[0].name)
                .select((x) ->
                    p = x.args[0]
                    provider: x.provider
                    module: x.module
                    probe: p.name
                    instant: p.instant
                    sampleThreshold: p.sampleThreshold
                    types: p.types
                )
                .subscribe report[command.report]
        doTimeout 1000

program
    .command('sample')
    .description('Subscribe to probe samples')
    .commonOptions()
    .option('-t, --timeout [milliseconds]', 'Time to wait before disconnect. (default: Infinity)', Number, Infinity)
    .option('-m, --mapbefore <expression>', 'Map expression before processing, right after --filterbefore.')
    .option('-M, --mapafter <expression>', 'Map expression after processing, right before the callback')
    .option('-f, --filterbefore <expression>', 'Filter using boolean expression at the beginning.')
    .option('-F, --filterafter <expression>', 'Filter using boolean expression right before --mapafter.')
    .option('-a, --aggregate <function(expression)>', 'Aggregate expression.')
    .option('-A, --aggregate2 <function>', 'Aggregate function to apply after --aggregate with --pair.\n'+
    '                                        Requires no --group.')
    .option('-g, --group <expression>', 'Group expression.')
    .option('-w, --window <span>[,shift]', 'Time window. <span> is the length of each window.\n'+
    '                                        [,shift] is the interval between creation of consecutive windows.')
    .option('-i, --interval <milliseconds>', 'Sampling interval.')
    .option('-P, --pair', 'Pair previous and current sample. Requires --aggregate and no --group.')
    .action (command) ->
        consumer.start {probeKey: command.probe, sampleInterval: command.interval},
            mapbefore: command.mapbefore
            mapafter: command.mapafter
            filterbefore: command.filterbefore
            filterafter: command.filterafter
            aggregate: command.aggregate
            aggregate2: command.aggregate2
            group: command.group
            window: command.window
            pair: command.pair
            callback: report[command.report]
        doTimeout command.timeout


exit = (code) ->
    consumer.stop()
    consumer.disconnect()
    process.exit code

doTimeout = (timeout) ->
    setTimeout ->
        exit 0
    , timeout

process.on 'SIGTERM', ->
    exit 1

process.on 'SIGINT', ->
    exit 1

report =
    object: (x) ->
        console.log util.inspect x, false, 5, not program.nocolor
    pretty: do ->
        formatFirst = true

        pad = (x, n) ->
            while x.length < Math.abs(n)
                if n < 0
                    x = ' ' + x
                else
                    x = x + ' '
            x

        formatHeader = (k,v) ->
            if typeof v is 'number'
                h = pad k, -15
            else if typeof v is 'boolean'
                h = pad k, 15
            else
                h = pad k, 20
            h.blue

        formatValue = (v) ->
            if not v?
                '<undefined>'
            else if typeof v is 'number'
                f = v.toFixed 3
                if f.slice(-3) is '000'
                    f = v.toString()
                r = pad f, -15
                r.grey
            else if typeof v is 'string'
                pad v, 20
            else if typeof v is 'boolean'
                r = pad v.toString(), 15
                r.yellow
            else if /Quantizer$/.test v.constructor.name
                formatQuantizer v
            else
                util.inspect v, false, 5, not program.nocolor

        formatQuantizer = (q) ->
            length = 50

            bar = (x) ->
                return '' if q.maxCount is 0
                x = (length - 1) * x / q.maxCount
                return pad '', length if x is 0
                x = [1..x].map(->'▒').join ''
                x = pad x, length
                x.red

            lines = []
            lines.push ''
            lines.push formatHeader('value', 0) + ' ' + pad('', length) + ' ' + formatHeader('count', 0)
            totalCount = 0
            for i in [q.minIndex..q.maxIndex] by 1
                count = q.count i
                totalCount += count
                lines.push formatValue(q.indexValue i) + '│' + bar(count) + '│' + formatValue(count)
            lines.push pad('', 15) + '│' + pad('total count ', -length).yellow + '│' + formatValue(totalCount).stripColors
            lines.push ''
            lines.join '\n'

        formatObject = (x) ->
            if x instanceof Array
                formatFirst = true
                result = ''
                x.forEach (y) ->
                    result += formatObject y
                return result

            if typeof x isnt 'object'
                return formatValue(x) + '\n'

            head = []
            line = []
            for key, value of x
                v = formatValue(value)
                if v?
                    line.push v
                    if formatFirst
                        head.push formatHeader(key, value)

            result = ''
            if line.length isnt 0
                if formatFirst
                    result += "\n"
                    result += head.join(' ') + "\n"
                    formatFirst = false
                result += line.join(' ') + "\n"
            result

        (x) ->
            result = formatObject x
            result = result.stripColors if program.nocolor
            process.stdout.write result


program
    .command('*')
    .action ->
      process.stdout.write(program.helpInformation())
      process.exit(0)

program
    .parse(process.argv)
