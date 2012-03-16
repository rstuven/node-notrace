{Consumer} = require '..'

consumer = new Consumer

consumer.start '*.*.random', (subject) ->
    s = subject

    # take one sample per second
    s = s.windowWithTime(1000).selectMany((x) -> x.take(1))

    # pair current sample with the next
    s = s.zip(s.skip(1), (cur, next) -> [cur, next])

    s.subscribe((x) ->
        swap = (x) -> x.args = [x.args[1], x.args[0]]
        swap x[0]; swap x[1]
        stats =
            a0: x[0].args
            a1: x[1].args
            t0: x[0].timestamp
            t1: x[1].timestamp
        [
            'elapsed_time'
            'delta'
            'fraction'
            'average'
            'rate_per_second'
            'multi_timer'
            'multi_timer_inverse'
            'average_timer'
        ]
            .forEach (k) -> stats[k] = calculate k, x[0], x[1]
        console.log stats
        console.log ''
        swap x[0]; swap x[1]
    )

consumer.stop wait: 3000, disconnect: true


# see http://msdn.microsoft.com/en-us/library/system.diagnostics.performancecountertype.aspx
calculate = (type, sampleOld, sampleNew) ->

    n0 = sampleOld.args[0]
    n1 = sampleNew.args[0]
    d0 = sampleOld.args[1]
    d1 = sampleNew.args[1]
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
