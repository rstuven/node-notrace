var Consumer = require('..').Consumer;

var consumer = new Consumer;

consumer.start('*.*.random', function(subject) {
  return subject
    // every 2 seconds
    .windowWithTime(2000)
    .selectMany(function(win) {
       return win
         // group samples by argument 0
         .groupBy(function(x) { return x.args[0]; })
         // count them and average argument 1.
         .selectMany(function(grp) {
            return grp.count().select(function(x) { return { key: grp.key, count: x }; })
            //.zip(grp.count(), function(f, r) { f.count = r; return f; })
            //.zip(grp.count(), function(f, r) { return { key: grp.key, count: r }; })
            .zip(grp.select(function(x) { return x.args[1]; }).average(), function(f, r) { f.average = r; return f; }); })
         .aggregate([], function(acc, x) { acc.push(x); return acc; });
    }).subscribe(function(x) {
        return console.log(x);
    });
});

consumer.stop({
  wait: 5000,
  disconnect: true
});
