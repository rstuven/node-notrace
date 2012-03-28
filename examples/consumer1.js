var Consumer = require('..').Consumer;

var consumer = new Consumer;

// consume a single sample
consumer.sample('*.*.random', function(sample) {
  return console.log(sample);
});
