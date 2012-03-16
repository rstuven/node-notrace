program = require 'commander'
{Provider} = require '..'
os = require 'os'

program
    .option('-p --provider [name]', 'Provider name', 'p')
    .option('-m --module [name]', 'Module name', 'm')
    .parse(process.argv)

provider = new Provider
    name: program.provider
    probes:
        os_uptime:              -> os.uptime()
        os_loadavg:             -> la = os.loadavg(); "1m":la[0], "5m":la[1], "15m":la[2]
        os_freemem:             -> os.freemem()
        os_totalmem:            -> os.totalmem()
        uptime:                 -> process.uptime()
        memory_heap_used:       -> process.memoryUsage().heapUsed
        memory_heap_total:      -> process.memoryUsage().heapTotal
        random:
            types: ['number', 'number']
            sampleThreshold: 0
        random_walk:
            types: ['number']
            sampleThreshold: 0
            instant: true

provider.start program.module

# random
do ->
    dist = [1..10]
    dist = dist.map (i) -> x = i/dist.length; Math.exp(-(Math.PI*x*x))
    interval = setInterval ->
        arg0 = Math.random()*1000
        index = Math.floor(Math.random()*dist.length)
        if dist[index] > Math.random()
            provider.probes.random.update index, arg0
    , 1 # beware!

# random_walk
do ->
    value = 0
    range = 256
    minValue = -1024
    maxValue = +1024
    toLoop = ->
        setTimeout ->
            value = Math.min(maxValue, Math.max(minValue, value + Math.random()*range-range/2))
            provider.probes.random_walk.update value
            toLoop()
        , 10 + Math.random()*500
    toLoop()
