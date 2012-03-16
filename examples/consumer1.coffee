{Consumer} = require '..'

consumer = new Consumer

# consume a single sample
consumer.sample '*.*.random', (sample) ->
    console.log sample
