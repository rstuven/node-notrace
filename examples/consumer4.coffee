{Consumer} = require '..'

consumer = new Consumer

consumer.start '*.*.random', (subject) ->
    subject
        # every 2 seconds
        .windowWithTime(2000)
        .selectMany((win)->
            # group samples by argument 0
            win.groupBy((x)-> x.args[0])
            # count them and average argument 1.
            .selectMany((grp) -> grp
                .count().select((x) -> {key: grp.key, count: x})
                #.zip(grp.count(), (f, r)-> f.count = r; f)
                #.zip(grp.count(), (f, r)-> { key: grp.key, count: r})
                .zip(grp.select((x)->x.args[1]).average(), (f, r)-> f.average = r; f)
                )
            .aggregate([], (acc, x) -> acc.push x; acc)
        )
        .subscribe (x) -> console.log x

consumer.stop wait: 5000, disconnect: true


