(function() {
  var Delay, EventEmitter, PROBE_DISABLE_DELAY, Probe, SAMPLE_THRESHOLD, Timer, uuid,
    __hasProp = Object.prototype.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; },
    __slice = Array.prototype.slice;

  EventEmitter = require('events').EventEmitter;

  uuid = require('uuid-v4.js');

  Delay = require('./timers').Delay;

  Timer = require('./timers').Timer;

  SAMPLE_THRESHOLD = 1000;

  PROBE_DISABLE_DELAY = 6000;

  /**
   * # Probe
   *
   * This class represents an instrumentation point.
   *
   * @class Probe
  */

  exports.Probe = Probe = (function(_super) {

    __extends(Probe, _super);

    function Probe() {
      var config, types;
      config = arguments[0], types = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      this.id = uuid();
      this.consumerTimers = {};
      this.disableDelay = new Delay;
      if (typeof config === 'string') {
        config = {
          name: config,
          types: types
        };
      }
      /**
       * # .name
       * Gets the probe name
      */
      if (!(config.name != null) || typeof config.name !== 'string' || config.name === '') {
        throw new Error("Argument is missing: 'name'");
      }
      if (config.name.match(/[\.#*]/)) {
        throw new Error('Invalid character in name. The following are reserved: .#*');
      }
      this.name = config.name;
      /**
       * # .types
       * Gets the array of argument types.
      */
      if ((!(config.types != null)) || (!config.types instanceof Array) || (config.types.length === 0)) {
        this.types = ['number'];
      } else {
        this.types = config.types;
      }
      /**
       * # .enabled
       * Gets the enabled status.
      */
      this.enabled = config.enabled === true;
      /**
       * # .instant
       * Gets or sets the instant property value.
       *
       * If true, the probe will emit a sample right after a change (see `update` and `increment` methods).
       *
       * If false, consumers must request samples for a specific time interval. See `start` method of `Consumer`.
       *
       * Set this property only at initialization. DO NOT modify it after the probe starts operating.
       *
      */
      this.instant = config.instant === true;
      /**
       * # .sampleThreshold
       * Gets the sample threshold value.
      */
      this.sampleThreshold = !(config.sampleThreshold != null) ? SAMPLE_THRESHOLD : config.sampleThreshold;
      /**
       * # .args
       * Gets the arguments.
      */
      if (config.args != null) {
        if (config.args instanceof Array) {
          this.args = config.args;
        } else {
          this.args = [config.args];
        }
        if (this.args.length === 1 && (typeof this.args[0] === 'function')) {
          this.args = this.args[0];
        }
      } else {
        this.args = this.types.map(function(type) {
          if (type === 'number') {
            return 0;
          } else {
            return '';
          }
        });
      }
      /**
       * # .hits
       * Gets the hits property value.
      */
      this.hits = 0;
    }

    /**
     * # .update()
     *
     * Updates a probe.
     *
     * Example:
     *     probe.update(123, 'abc');
     *
     * @param {params} args The arguments of the probe.
    */

    Probe.prototype.update = function() {
      var args,
        _this = this;
      args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
      this.args = args;
      this.hits++;
      if (this.enabled && this.instant) {
        return this.evaluate(this.args, function(err, evaluated, timestamp) {
          return _this.sample(null, null, evaluated, timestamp);
        });
      }
    };

    /**
     * # .increment()
     *
     * Increments a probe.
     *
     * Example:
     *     probe.increment();
     *
     * @param {Number} offset (Optional) The increment offset. It can ben positive or negative. Default: +1.
     * @param {Number} index (Optional) The argument index. Default: 0.
    */

    Probe.prototype.increment = function(offset, index) {
      var arg;
      if (offset == null) offset = 1;
      if (index == null) index = 0;
      arg = this.args[index];
      if (typeof arg !== 'number') {
        throw new Error("Argument of wrong type. args in index " + index + " can not be incremented.");
      }
      this.args[index] = arg + offset;
      this.hits++;
      if (this.enabled && this.instant) return this.sample(null, null, this.args);
    };

    Probe.prototype.sample = function(consumerId, callback, args, timestamp) {
      var go, now,
        _this = this;
      now = Date.now();
      if (!(this.sampleThreshold === 0 || !(this.lastTimestamp != null) || (now - this.lastTimestamp) >= this.sampleThreshold)) {
        return;
      }
      this.lastTimestamp = now;
      go = function(err, v, ts) {
        var sample;
        sample = {
          timestamp: ts || Date.now(),
          hits: _this.hits,
          args: v,
          error: err
        };
        _this.emit('sample', sample, consumerId);
        if (callback != null) return callback(null, sample, consumerId);
      };
      if (args != null) {
        return go(null, args, timestamp);
      } else {
        return this.evaluate(this.args, go);
      }
    };

    Probe.prototype.evaluate = function(args, callback) {
      var cb, r;
      if (typeof args === 'function') {
        cb = function(err, result, timestamp) {
          if (err) {
            callback(err);
            return;
          }
          if (result instanceof Array) {
            return callback(null, result, timestamp);
          } else {
            return callback(null, [result], timestamp);
          }
        };
        try {
          r = args(cb);
        } catch (e) {
          callback(e);
          return;
        }
        if (r != null) return cb(null, r);
      } else {
        return callback(null, args);
      }
    };

    Probe.prototype.enableForConsumer = function(consumerId, interval, probeKey) {
      var timer,
        _this = this;
      this.enabled = true;
      if (!this.instant) {
        if (interval > 0 && !(this.consumerTimers[consumerId] != null)) {
          timer = new Timer;
          this.consumerTimers[consumerId] = timer;
          timer.start(interval, function() {
            return _this.sample(consumerId);
          });
        }
        return this.disableDelay.start(PROBE_DISABLE_DELAY, function() {
          var consumerId, timer, _ref;
          _this.enabled = false;
          _ref = _this.consumerTimers;
          for (consumerId in _ref) {
            timer = _ref[consumerId];
            timer.stop();
          }
          return _this.consumerTimers = {};
        });
      }
    };

    Probe.prototype.stop = function(consumerId) {
      var timer;
      if (this.instant) {
        return this.enabled = false;
      } else {
        timer = this.consumerTimers[consumerId];
        if (timer != null) {
          timer.stop();
          return delete this.consumerTimers[consumerId];
        }
      }
    };

    return Probe;

  })(EventEmitter);

}).call(this);
