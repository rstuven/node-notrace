var Consumer = require('..').Consumer;

var consumer = new Consumer;

consumer.start('*.*.random', function(subject) {
  var s = subject;

  // take one sample per second
  s = s.windowWithTime(1000).selectMany(function(x) { return x.take(1); });

  // pair current sample with the next
  s = s.zip(s.skip(1), function(cur, next) { return [cur, next]; });

  s.subscribe(function(x) {
    var swap = function(x) {
      x.args = [x.args[1], x.args[0]];
    };
    swap(x[0]);
    swap(x[1]);
    var stats = {
      a0: x[0].args,
      a1: x[1].args,
      t0: x[0].timestamp,
      t1: x[1].timestamp
    };
    ['elapsed_time', 'delta', 'fraction', 'average', 'rate_per_second', 'multi_timer', 'multi_timer_inverse', 'average_timer'].forEach(function(k) {
      stats[k] = calculate(k, x[0], x[1]);
    });
    console.log(stats);
    console.log('');
    swap(x[0]);
    swap(x[1]);
  });
});

consumer.stop({
  wait: 3000,
  disconnect: true
});

// see http://msdn.microsoft.com/en-us/library/system.diagnostics.performancecountertype.aspx
calculate = function(type, sampleOld, sampleNew) {
  var d0, d1, n0, n1, t0, t1;
  n0 = sampleOld.args[0];
  n1 = sampleNew.args[0];
  d0 = sampleOld.args[1];
  d1 = sampleNew.args[1];
  t0 = sampleOld.timestamp;
  t1 = sampleNew.timestamp;
  switch (type) {
    case 'elapsed_time':
      return t1 - t0;
    case 'delta':
      return n1 - n0;
    case 'fraction':
      return n0 / d0;
    case 'average':
      return (n1 - n0) / (d1 - d0);
    case 'rate_per_millisecond':
      return (n1 - n0) / (t1 - t0);
    case 'rate_per_second':
      return (n1 - n0) / (t1 - t0) * 1000;
    case 'multi_timer':
      return (n1 - n0) / (t1 - t0) * 100 / d1;
    case 'average_timer':
      return (n1 - n0) / (t1 - t0) / (d1 - d0);
    case 'multi_timer_inverse':
      return (d1 - (n1 - n0) / (t1 - t0)) * 100;
    case 'timer_100_ns_inverse':
      return (1 - (n1 - n0) / (t1 - t0)) * 100;
  }
};
