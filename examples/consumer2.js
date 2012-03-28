var Consumer = require('..').Consumer;

var consumer = new Consumer;

// consume samples during 500 milliseconds, then disconnect.
consumer.start('*.*.random', function(subject) {
  return subject.subscribe(function(sample) {
    return console.log(sample);
  });
});

consumer.stop({
  wait: 500,
  disconnect: true
});

// can't start or sample again while it's busy.
console.log('busy?', consumer.isBusy());

// try uncommenting the following lines:
/*
consumer.sample('*.*.random', function(sample) {
  return console.log(sample);
});
*/
