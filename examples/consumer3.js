var Consumer = require('..').Consumer;

var consumer = new Consumer;

// consume samples during 3 seconds, aggregate values every 1 second.
consumer.start('*.*.random', function(subject) {
  return subject
    .select(function(x) { return x.args[1]; })
    .windowWithTime(1000)
    .selectMany(function(win) { return win.sum(); })
    //.selectMany(function(win) { return win.average(); })
    .subscribe(function(x) { return console.log(x); });
});

consumer.stop({
  wait: 3000,
  disconnect: true
});
