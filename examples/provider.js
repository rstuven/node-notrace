var program = require('commander'),
    Provider = require('..').Provider,
    os = require('os');

program
    .option('-p --provider [name]', 'Provider name', 'p')
    .option('-m --module [name]', 'Module name', 'm')
    .parse(process.argv);

provider = new Provider({
  name: program.provider,
  probes: {
    os_uptime:          function() { return os.uptime(); },
    os_loadavg:         function() { var la = os.loadavg(); return { "1m": la[0], "5m": la[1], "15m": la[2] }; },
    os_freemem:         function() { return os.freemem(); },
    os_totalmem:        function() { return os.totalmem(); },
    uptime:             function() { return process.uptime(); },
    memory_heap_used:   function() { return process.memoryUsage().heapUsed; },
    memory_heap_total:  function() { return process.memoryUsage().heapTotal; },
    random: {
      types: ['number', 'number'],
      sampleThreshold: 0
    },
    random_walk: {
      types: ['number'],
      sampleThreshold: 0,
      instant: true
    }
  }
});

provider.start(program.module);

//random
(function() {
    var dist = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    dist = dist.map(function(i) {
        var x = i / dist.length;
        return Math.exp(-(Math.PI * x * x));
    });
    setInterval(function() {
        var arg0 = Math.random() * 1000,
            index = Math.floor(Math.random() * dist.length);
        if (dist[index] > Math.random()) {
            provider.probes.random.update(index, arg0);
        }
    }, 1 /* beware! */);
})();

// random_walk
(function() {
  var value = 0,
      range = 256,
      minValue = -1024,
      maxValue = +1024,
      toLoop = function() {
          setTimeout(function() {
              value = Math.min(maxValue, Math.max(minValue, value + Math.random() * range - range / 2));
              provider.probes.random_walk.update(value);
              toLoop();
          }, 10 + Math.random() * 500);
      };
  toLoop();
})();
