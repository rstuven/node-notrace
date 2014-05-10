(function() {
  var BSON, CONNECTION_END_WAIT, Consumer, Delay, LinearQuantizer, Pow2Quantizer, RECONNECT_INTERVAL, REQUEST_ENABLE_INTERVAL, REQUEST_SAMPLE_INTERVAL, Timer, amqp, colors, exchanges, rx, uuid, _ref,
    __slice = Array.prototype.slice;

  amqp = require('amqp');

  uuid = require('uuid-v4.js');

  colors = require('colors');

  rx = require('rx');

  BSON = require('bson/lib/bson/bson').BSON;

  Delay = require('./timers').Delay;

  Timer = require('./timers').Timer;

  _ref = require('./quantizer'), Pow2Quantizer = _ref.Pow2Quantizer, LinearQuantizer = _ref.LinearQuantizer;

  exchanges = require('./exchanges');

  rx.Observable.prototype.quantize = function() {
    return this.aggregate(new Pow2Quantizer, function(q, v) {
      q.add(v);
      return q;
    });
  };

  rx.Observable.prototype.lquantize = function(lb, ub, sv) {
    return this.aggregate(new LinearQuantizer(lb, ub, sv), function(q, v) {
      q.add(v);
      return q;
    });
  };

  CONNECTION_END_WAIT = 30000;

  RECONNECT_INTERVAL = 1000;

  REQUEST_ENABLE_INTERVAL = 5000;

  REQUEST_SAMPLE_INTERVAL = 100;

  /**
   * # Consumer
   *
   * This class enables specific probes, receives samples and provide facilities for aggregation of samples.
   *
   * @class Consumer
  */

  exports.Consumer = Consumer = (function() {
    /**
     * @constructor
     * @param {Object} config (Optional) The configuration object.
    */
    var generateObservable, pairAggregation;

    function Consumer(config) {
      this.config = config != null ? config : {};
      this.id = uuid();
      this.reconnectTimer = new Timer;
      this.requestEnableTimer = new Timer;
      this.connectionEndDelay = new Delay;
    }

    /**
     * # .sample()
     * Requests a single sample using probe key.
     * @param {String} probeKey The probe key with the format "provider.module.probe".
     * @param {Function} callback The callback function receives a 'subject' argument.
    */

    Consumer.prototype.sample = function(probeKey, callback) {
      var _this = this;
      return this.start(probeKey, function(subject) {
        return subject.subscribe(function(x) {
          callback(x);
          return _this.stop();
        });
      });
    };

    /**
     * # .start() [1]
     *
     * Starts a subscription to samples using probe key.
     *
     * A probe key has the format `provider.module.probe` and allows to use a `*` wildcard instead of each part. For example, the probe key `*.*.uptime` matches any probe named "uptime" of any provider in any module.
     *
     * The callback function receives a `subject` argument. Subject is an RxJS object that allows to subscribe to a stream of samples and processing them as they arrive using a powerful API.
     *
     * Examples:
     *
     * Receive a stream of samples.
     *
     *     consumer.start('*.*.myprobe', function (subject) {
     *       subject.subscribe(function (sample) {
     *         console.log(sample); // prints all arriving samples
     *       });
     *     });
     *
     * Calculate an average per second.
     *
     *     consumer.start('*.*.myprobe', function (subject) {
     *       subject
     *         .select(function (x) { return x.args[0]; })
     *         .windowWithTime(1000)
     *         .selectMany(function (win) { return win.average(); })
     *         .subscribe(function (x) { console.log(x); }); // prints a number every second
     *     });
     *
     * Calculate an average per second per module. Now this requires a little more involved use of bare RxJS. This can be simplified a lot using a `callbackConfig`.
     *
     *     consumer.start('*.*.myprobe', function (subject) {
     *       subject
     *         .windowWithTime(1000)
     *         .selectMany(function (win) {
     *           var agg = win
     *             .groupBy(function (x) { return x.module; })
     *             .selectMany(function (grp) {
     *               return grp.count().select(function (x) { return { module: grp.key, count: x }; }).zip(
     *                      grp.select(function (x) { return x.args[0]; }).average(),
     *                          function (f, r) { f.average = r; return f; });
     *             })
     *             .aggregate([], function (acc, x) { acc.push(x); return acc; });
     *           return agg;
     *         })
     *         .subscribe(function (x) { console.log(x); });
     *         // prints every second something like: [ {module:'a', average: 123}, {module:'b', average: 456} ]
     *     });
     *
     * @param {String} probeKey The probe key with the format "provider.module.probe".
     * @param {Function} callback The callback function receives a 'subject' argument.
    */

    /**
     * # .start() [2]
     *
     * Starts a subscription to samples using configuration objects.
     *
     * *callbackConfig* argument can have the following properties:
     *
     * - `mapbefore`: {String} Map expression before grouping and aggregating, evaluated right after `filterbefore`.
     * - `mapafter`: {String} Map expression after grouping and aggregating, evaluated right before the callback.
     * - `filterbefore`: {String} Filter using boolean expression at the beginning.
     * - `filterafter`: {String} Filter using boolean expression, evaluated right before `mapafter`.
     * - `aggregate`: {String} Aggregate function over expression.
     *  - Available aggregation functions are:
     *    - *count()*
     *    - *sum(expression)*
     *    - *min(expression)*
     *    - *max(expression)*
     *    - *average(expression)*
     *    - *quantize(expression)*
     *    - *lquantize(expression; lowerBound; upperBound; stepValue)*
     *  - Using `pair`, available aggregations are:
     *    - *elapsed_time()*
     *    - *delta(expression)*
     *    - *fraction(expression)*
     *    - *rate_per_millisecond(expression)*
     *    - *rate_per_second(expression)*
     *    - *average(expression1, expression2)*
     *    - *average_timer(expression1, expression2)*
     *    - *multi_timer(expression1, expression2)*
     *    - *multi_timer_inverse(expression1, expression2)*
     * - `aggregate2`: {String} Aggregate function to apply after `aggregate` with `pair`. Requires no `group` be specified.
     * - `group`: {String} Group expression.
     * - `window`: {String} Time window in the format `span[,shift]`. `span` is the length of each window. `[,shift]` is the optional interval between creation of consecutive windows.
     * - `pair`: {Boolean} Pair previous and current sample. Requires `aggregate` and no `group` be specified.
     * - `callback`: {Function} Callback function that receives result of processing.
     *
     * Expressions required above are strings containing JavaScript expressions. Sample properties are available as variables, unless a mapping or aggregating operation is applied.
     *
     * Examples:
     *
     * During 5 seconds, count how many samples per module there are:
     *
     *     consumer.start('*.*.random_walk', {
     *         aggregate: 'count()',
     *         group: 'module',
     *         callback: function(result) { console.log(result); }
     *     });
     *     consumer.stop({wait: 5000});
     *
     * During 1500 ms, every 500 ms, take a 1 second of samples, group them by module and average the first argument:
     *
     *     consumer.start('*.*.random_walk', {
     *         aggregate: 'average(args[0])',
     *         group: 'module',
     *         window: '1000,500',
     *         callback: function(result) { console.log(result); }
     *     });
     *     consumer.stop({wait: 1500});
     *
     * During 1 second, calculate the differences between a value and the next, then aggregate them all using quantize:
     *
     *     consumer.start('*.*.random_walk', {
     *         pair: true,
     *         aggregate: 'delta(args[0])',
     *         aggregate2: 'quantize',
     *         callback: function(result) { console.log(result); }
     *     });
     *     consumer.stop({wait: 1000});
     *
     * During 1 second, filter all values below 20, count per every 100 ms, filter counts above 0:
     *
     *     consumer.start({
     *       probeKey: '*.*.random',
     *       sampleInterval: 1 // request the matching probes to emit a sample every 1 millisecond.
     *     }, {
     *         filterbefore: 'args[1] < 20',
     *         window: '100',
     *         aggregate: 'count()',
     *         filterafter: 'count > 0',
     *         callback: function(sample) { console.log(sample); }
     *     });
     *     consumer.stop({wait: 1000});
     *
     * @param {Object} probeConfig The probe configuration object.
     * @param {Object} callbackConfig The callback configuration object.
    */

    Consumer.prototype.start = function(config, callback) {
      var probeKey,
        _this = this;
      if (this.isBusy()) throw new Error('Consumer is busy. It must stop first.');
      if (typeof callback === 'object') {
        this.start(config, function(subject) {
          return generateObservable(callback, subject).subscribe(callback.callback);
        });
        return;
      }
      if (typeof config === 'string') {
        probeKey = config;
      } else {
        probeKey = config.probeKey;
      }
      if ((config != null) && (config.sampleInterval != null)) {
        this.sampleInterval = config.sampleInterval;
      } else {
        this.sampleInterval = REQUEST_SAMPLE_INTERVAL;
      }
      probeKey = probeKey.replace(/^\./, '*.');
      probeKey = probeKey.replace(/\.$/, '.*');
      probeKey = probeKey.replace(/\.\./, '.*.');
      this.probeKey = probeKey;
      this.subject = new rx.Subject;
      callback(this.subject);
      this.connect();
      return this.reconnectTimer.start(RECONNECT_INTERVAL, function() {
        if (!(_this.connection != null)) return _this.connect();
      });
    };

    /**
     * # .stop()
     *
     * Stops the current subscription to samples.
     *
     * It can be configured to wait a time before stopping (by default is immediate) and disconnect right away (by default, the connections remains open for some time, which is good for new subscriptions but a console application, for example, won't exit until the connection ends).
     *
     * Examples:
     *     consumer.stop(); // stop receiving samples, stay connected for the next subscription.
     *
     *     consumer.stop({
     *         wait: 5000, // stop after 5 seconds.
     *         disconnect: true
     *     });
     *
     * @param {Object} config.
    */

    Consumer.prototype.stop = function(config) {
      var wait,
        _this = this;
      if (config == null) config = {};
      if (config.wait != null) {
        wait = config.wait;
        delete config.wait;
        setTimeout(function() {
          return _this.stop(config);
        }, wait);
        return;
      }
      this.reconnectTimer.stop();
      this.requestEnableTimer.stop();
      this.request(this.probeKey, 'stop');
      if (this.subject != null) {
        this.subject.onCompleted();
        this.subject = null;
      }
      if (this.queue != null) {
        this.queue.destroy();
        this.queue = null;
      }
      return this.disconnect(config.disconnect === true);
    };

    Consumer.prototype.request = function() {
      var args, message, probeKey, request;
      probeKey = arguments[0], request = arguments[1], args = 3 <= arguments.length ? __slice.call(arguments, 2) : [];
      if (!(this.requests != null)) return;
      message = {
        request: request,
        probeKey: probeKey,
        consumerId: this.id,
        args: args
      };
      message = BSON.serialize(message);
      try {
        return this.requests.publish('', message);
      } catch (e) {
        return this.disconnect();
      }
    };

    Consumer.prototype.connect = function() {
      var host,
        _this = this;
      this.connectionEndDelay.stop();
      if (this.connection != null) {
        this.open();
        return;
      }
      host = this.config.host || 'localhost';
      this.connection = amqp.createConnection({
        host: host
      });
      this.connection.on('error', function(err) {
        console.error(err);
        return _this.disconnect();
      });
      return this.connection.on('ready', function() {
        return _this.open();
      });
    };

    Consumer.prototype.open = function() {
      var _this = this;
      return exchanges.requests(this.connection, function(exchange) {
        if (!(_this.connection != null)) return;
        _this.requests = exchange;
        _this.request(_this.probeKey, 'enable', _this.sampleInterval);
        _this.requestEnableTimer.start(REQUEST_ENABLE_INTERVAL, function() {
          return _this.request(_this.probeKey, 'enable', _this.sampleInterval);
        });
        return exchanges.samples(_this.connection, function(exchange) {
          if (!(_this.connection != null)) return;
          _this.samples = exchange;
          return _this.connection.queue('', function(queue) {
            if (!(_this.connection != null)) return;
            _this.queue = queue;
            queue.bind(_this.samples.name, _this.probeKey + '.' + _this.id);
            queue.bind(_this.samples.name, _this.probeKey + '.all');
            queue.subscribe({
              ack: false,
              exclusive: true
            }, function(message) {
              message = BSON.deserialize(message.data);
              if (_this.subject != null) return _this.subject.onNext(message);
            });
            return _this.request(_this.probeKey, 'sample');
          });
        });
      });
    };

    /**
     * # .disconnect()
     *
     * Disconnects from server.
     *
     * @param {Boolean} immediate Specifies whether to disconnect immediately or to wait a few seconds
    */

    Consumer.prototype.disconnect = function(immediate) {
      var _this = this;
      if (immediate == null) immediate = true;
      if (this.samples != null) this.samples = null;
      if (this.requests != null) this.requests = null;
      this.connectionEndDelay.stop();
      if (immediate) {
        if (this.connection != null) {
          this.connection.end();
          return this.connection = null;
        }
      } else {
        return this.connectionEndDelay.start(CONNECTION_END_WAIT, function() {
          if (_this.connection != null) {
            _this.connection.end();
            return _this.connection = null;
          }
        });
      }
    };

    /**
     * # .isBusy()
     * Gets the busy state. When a subscription starts, we say the consumer is busy. When the subscription stops, the consumer is not busy.
     * @return {Boolean} The busy state.
    */

    Consumer.prototype.isBusy = function() {
      return this.subject != null;
    };

    /**
     * # RxJS query generation.
     * Please, view source.
    */

    generateObservable = function(config, subject) {
      var aggBy, aggBy2, aggCode, aggFn, aggMatches, aggName, code, expression, func, globalProp, globalProps, groupCode, highlight, windowCode;
      expression = function(e) {
        return "function(_){return(function(){with(_){return " + (highlight(e)) + ";}}).call(global);}";
      };
      highlight = function(c) {
        if (c != null) return c.grey;
      };
      code = '';
      globalProps = (function() {
        var _results;
        _results = [];
        for (globalProp in global) {
          if (globalProp !== 'console') _results.push(globalProp);
        }
        return _results;
      })();
      code += "\nvar " + (globalProps.join(',')) + ";";
      code += '\nglobal = {};';
      code += '\nvar s = subject;';
      if (config.filterbefore != null) {
        code += "s = s.where(" + (expression(config.filterbefore)) + ");";
      }
      if (config.mapbefore != null) {
        code += "s = s.select(" + (expression(config.mapbefore)) + ");";
      }
      if (config.aggregate != null) {
        aggMatches = config.aggregate.match(/^\s*([^\(]+)\(([^;]*)(?:;(.*))?\)\s*$/);
        if (!(aggMatches != null)) throw new Error("Invalid aggregate format");
        aggFn = aggMatches[1];
        aggBy = aggMatches[2];
        aggBy2 = aggMatches[3];
        if (aggBy2 != null) aggBy2 = aggBy2.replace(/;/g, ',');
        if ((aggBy != null) && aggBy.trim() !== '') {
          aggCode = ".select(" + (expression(aggBy)) + ")";
        } else {
          aggCode = "";
        }
        aggCode += "." + (highlight(aggFn)) + "(" + (highlight(aggBy2)) + ")";
        aggName = aggFn;
      } else {
        aggCode = ".take(1)";
        aggName = "sample";
      }
      if (config.group != null) {
        groupCode = aggCode;
        groupCode += ".select(function(_){return {key:grp.key, " + (highlight(aggName)) + ":_};})";
        windowCode = ".groupBy(" + (expression(config.group)) + ")";
        windowCode += ".selectMany(function(grp){return grp" + groupCode + ";})";
        if (config.filterafter != null) {
          windowCode += ".where(" + (expression(config.filterafter)) + ")";
        }
        windowCode += ".aggregate([], function(acc, _){ acc.push(_); return acc;})";
      } else if (config.pair) {
        windowCode = ".take(1)";
      } else {
        windowCode = aggCode;
        if (config.aggregate != null) {
          windowCode += ".select(function(_){return {" + (highlight(aggName)) + ":_};})";
        }
      }
      if (config.window != null) {
        code += "s = s.windowWithTime(" + (highlight(config.window)) + ");";
        code += "s = s.selectMany(function(win){return win" + windowCode + ";});";
      } else if ((config.aggregate != null) && !config.pair) {
        code += "s = s" + windowCode + ";";
      }
      if ((config.aggregate != null) && config.pair && !(config.group != null)) {
        code += "s = s.zip(s.skip(1), function(p,c){return {prev:p, cur:c};});";
        code += "s = s.select(function(_){return pairAggregation('" + (highlight(aggFn)) + "'";
        code += "," + (expression(aggBy));
        code += "," + (expression(aggBy2));
        code += ",_.prev, _.cur);});";
        if (config.aggregate2 != null) {
          code += "s = s." + (highlight(config.aggregate2)) + "().select(function(_){return {\"" + (highlight(config.aggregate2)) + " " + (highlight(aggFn)) + "\":_};});";
        } else {
          code += "s = s.select(function(_){return {" + (highlight(aggFn)) + ":_};});";
        }
      }
      if ((config.filterafter != null) && !(config.group != null)) {
        code += "s = s.where(" + (expression(config.filterafter)) + ");";
      }
      if (config.mapafter != null) {
        code += "s = s.select(" + (expression(config.mapafter)) + ");";
      }
      code += "\nreturn s;";
      code = code.replace(/(s = s\.)/g, '\n$1');
      code = code.stripColors;
      func = new Function('subject', 'pairAggregation', code);
      return func.call({}, subject, pairAggregation);
    };

    /**
     * # Pair aggregation.
     * Please, view source.
    */

    pairAggregation = function(type, nFn, dFn, sampleOld, sampleNew) {
      var d0, d1, n0, n1, t0, t1;
      n0 = nFn(sampleOld);
      n1 = nFn(sampleNew);
      d0 = dFn(sampleOld);
      d1 = dFn(sampleNew);
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

    return Consumer;

  })();

}).call(this);
