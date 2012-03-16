{Consumer} = require '..'

consumer = new Consumer

# consume samples during 3 seconds, aggregate values every 1 second.
consumer.start '*.*.random', (subject) ->
    subject
        .select((x) -> x.args[1])
        .windowWithTime(1000)
        .selectMany((win)-> win.sum())
        #.selectMany((win)-> win.average())
        .subscribe (x) -> console.log x

consumer.stop wait: 3000, disconnect: true
