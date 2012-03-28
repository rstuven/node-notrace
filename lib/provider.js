(function() {
  var BSON, EventEmitter, Probe, Provider, RECONNECT_INTERVAL, Timer, amqp, exchanges,
    __hasProp = Object.prototype.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; },
    __slice = Array.prototype.slice;

  amqp = require('amqp');

  EventEmitter = require('events').EventEmitter;

  BSON = require('bson/lib/bson/bson').BSON;

  Probe = require('./probe').Probe;

  Timer = require('./timers').Timer;

  exchanges = require('./exchanges');

  RECONNECT_INTERVAL = 5000;

  /**
   * # Provider
   *
   * This class is instantiatied by applications that need to be instrumentalized. A provider can be seen as the container of a category of probes.
   *
   * All providers defines a probe by default: `_probes`. This probe returns all probes defined in its provider.
   *
   * @class Provider
  */

  exports.Provider = Provider = (function(_super) {

    __extends(Provider, _super);

    /**
     * Examples:
     *     // Probes can be defined using sync or async functions:
     *     // Not shown in this example, but this could be useful to call system stats tools.
     *     // (eg. mpstat, iostat, etc.)
     *     var p = new Provider({
     *       name: 'myprovider',
     *       probes: {
     *         // sync
     *         memory_heap_used: function () {
     *           return process.memoryUsage().heapUsed;
     *         },
     *         // async
     *         files_count: function (callback) {
     *           fs.readdir('/some/path', function (err, files) {
     *             if (err)
     *               callback(err);
     *             else
     *               // there could be multiple calls to callback in the same function.
     *               callback(null, files.length);
     *           });
     *         }
     *       }
     *     });
     * @constructor
     * @param {Object} config (Optional) The configuration object.
    */

    function Provider(config) {
      var args, name, _ref,
        _this = this;
      this.config = config;
      if (!(this.config != null) || !(this.config.name != null)) {
        throw new Error("Argument missing: config.name");
      }
      this.reconnectTimer = new Timer;
      /**
       * # .probes
       *
       * Gets defined probes.
       *
       * Example:
       *     var provider = new Provider({
       *         name: 'test',
       *         probes: {
       *             calls: ['number']
       *         }
       *     });
       *     provider.probes.calls.increment();
      */
      this.probes = {};
      if (this.config.probes != null) {
        _ref = this.config.probes;
        for (name in _ref) {
          args = _ref[name];
          if (typeof args === 'function') {
            args = {
              args: args
            };
          }
          args.name = name;
          this.addProbe(args);
        }
      }
      this.addProbe({
        name: '_probes',
        sampleThreshold: 0,
        instant: true,
        types: ['object'],
        args: function(cb) {
          var name, probe, _ref2;
          _ref2 = _this.probes;
          for (name in _ref2) {
            probe = _ref2[name];
            cb(null, {
              name: name,
              types: probe.types,
              instant: probe.instant,
              sampleThreshold: probe.sampleThreshold
            });
          }
          return;
        }
      });
    }

    /**
     * # .addProbe()
     *
     * Adds a probe definition.
     *
     * Examples:
     *
     *     provider.addProbe('msg', 'string');
     *     provider.addProbe({
     *       name: 'uptime',
     *       args: function() { return process.uptime(); }
     *     });
     *
     * @param {String} name The name of the probe.
     * @param {params String} args The type of each argument.
    */

    Provider.prototype.addProbe = function() {
      var args, name, probe,
        _this = this;
      name = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      probe = (function(func, args, ctor) {
        ctor.prototype = func.prototype;
        var child = new ctor, result = func.apply(child, args);
        return typeof result === "object" ? result : child;
      })(Probe, [name].concat(__slice.call(args)), function() {});
      if (typeof name === 'object') name = name.name;
      this.probes[name] = probe;
      probe.on('sample', function(sample, consumerIds) {
        var consumerId, message, probeKey, _i, _len, _results;
        _this.emit('sample', probe, sample, consumerIds);
        if (!(_this.samples != null)) return;
        message = {
          provider: _this.config.name,
          module: _this.module,
          probe: probe.name,
          timestamp: sample.timestamp,
          hits: sample.hits
        };
        if (sample.args != null) message.args = sample.args;
        if (sample.error != null) message.error = sample.error.toString();
        message = BSON.serialize(message);
        probeKey = "" + _this.config.name + "." + _this.module + "." + probe.name;
        try {
          _results = [];
          for (_i = 0, _len = consumerIds.length; _i < _len; _i++) {
            consumerId = consumerIds[_i];
            _results.push(_this.samples.publish(probeKey + '.' + consumerId, message));
          }
          return _results;
        } catch (e) {
          return _this.disconnect();
        }
      });
      return probe;
    };

    /**
     * # .update()
     *
     * Updates a probe.
     *
     * Also checks if the probe exists and creates it if not,
     * which adds overhead, so use this method only for prototyping probes.
     * Prefer declaring the probe on provider creation and access it through 'probes' property.
     *
     * Example:
     *     provider.update('cache_size', cache.size());
     *
     * @param {String} name The name of the probe.
     * @param {params} args The arguments of the probe.
    */

    Provider.prototype.update = function() {
      var args, name, probe;
      name = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      probe = this.probes[name.name || name];
      if (!(probe != null)) probe = this.addProbe(name);
      return probe.update.apply(probe, args);
    };

    /**
     * # .increment()
     *
     * Increments a probe.
     *
     * Also checks if the probe exists and creates it if not,
     * which adds overhead, so use this method only for prototyping probes.
     * Prefer declaring the probe on provider creation and access it through 'probes' property.
     *
     * Example:
     *     provider.increment('rows', rows);
     *
     * @param {String} name The name of the probe.
     * @param {params} args The arguments of the probe increment.
    */

    Provider.prototype.increment = function() {
      var args, name, probe;
      name = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      probe = this.probes[name.name || name];
      if (!(probe != null)) probe = this.addProbe(name);
      return probe.increment.apply(probe, args);
    };

    /**
     * # .sample()
     *
     * Updates a probe and emits a sample if possible.
     *
     * Also checks if the probe exists and creates it if not,
     * which adds overhead, so use this method only for prototyping probes.
     * Prefer declaring the probe on provider creation and access it through 'probes' property.
     *
     * Example:
     *     provider.sample('log', 'error', 'this is it!');
     *
     * @param {String} name The name of the probe.
     * @param {params} args The arguments of the probe.
    */

    Provider.prototype.sample = function() {
      var args, name, probe;
      name = arguments[0], args = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      probe = this.probes[name.name || name];
      if (!(probe != null)) probe = this.addProbe(name);
      probe.instant = true;
      return probe.update.apply(probe, args);
    };

    /**
     * # .start()
     *
     * Starts the provider. This internally means connect to server.
     * Provider definitions can be reused across modules, so we must specify in what module we are.
     *
     * Example:
     *     provider.start('my_restful_api');
     *
     * @param {String} module The name of the module that is hosting the provider instance.
    */

    Provider.prototype.start = function(module) {
      var _this = this;
      this.module = module;
      this.connect();
      return this.reconnectTimer.start(RECONNECT_INTERVAL, function() {
        if (!(_this.connection != null)) return _this.connect();
      });
    };

    Provider.prototype.connect = function() {
      var doRequest, host, processRequestMessage,
        _this = this;
      host = this.config.host || 'localhost';
      this.connection = amqp.createConnection({
        host: host
      });
      this.connection.on('error', function(err) {
        console.log(err);
        return _this.disconnect();
      });
      this.connection.on('ready', function() {
        exchanges.samples(_this.connection, function(exchange) {
          if (!(_this.connection != null)) return;
          return _this.samples = exchange;
        });
        return exchanges.requests(_this.connection, function(exchange) {
          if (!(_this.connection != null)) return;
          _this.requests = exchange;
          return _this.connection.queue('', function(queue) {
            queue.bind(exchange.name, '');
            return queue.subscribe({
              ack: false,
              exclusive: true
            }, processRequestMessage);
          });
        });
      });
      processRequestMessage = function(message) {
        var matches, probeName, probes;
        message = BSON.deserialize(message.data);
        if (!(message.request != null)) return;
        if (!(message.probeKey != null)) return;
        if (!(message.consumerId != null)) return;
        matches = /^([^\.]+)\.([^\.]+)\.([^\.]+)$/.exec(message.probeKey);
        if (!(matches != null)) return;
        if (['*', _this.config.name].indexOf(matches[1]) === -1) return;
        if (['*', _this.module].indexOf(matches[2]) === -1) return;
        probeName = matches[3];
        probes = probeName === '*' ? Object.keys(_this.probes) : [probeName];
        return probes.forEach(function(probeName) {
          var probe;
          probe = _this.probes[probeName];
          if (probe != null) return doRequest(probe, message);
        });
      };
      return doRequest = function(probe, message) {
        var probeKey;
        probeKey = "" + _this.config.name + "." + _this.module + "." + probe.name;
        console.log("" + message.request + " " + probeKey);
        switch (message.request) {
          case 'sample':
            return probe.sample(message.consumerId);
          case 'enable':
            return probe.enableForConsumer(message.consumerId, message.args[0], probeKey);
          case 'stop':
            return probe.stop(message.consumerId);
        }
      };
    };

    /**
     * # .stop()
     *
     * Stops the provider.
     *
     * Example:
     *     provider.stop();
    */

    Provider.prototype.stop = function() {
      this.reconnectTimer.stop();
      return this.disconnect();
    };

    Provider.prototype.disconnect = function() {
      if (this.samples != null) this.samples = null;
      if (this.requests != null) this.requests = null;
      if (this.connection != null) {
        this.connection.end();
        return this.connection = null;
      }
    };

    return Provider;

  })(EventEmitter);

}).call(this);
