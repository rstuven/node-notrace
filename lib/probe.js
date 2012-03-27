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

  exports.Probe = Probe = (function(_super) {

    __extends(Probe, _super);

    function Probe() {
      var config, types;
      config = arguments[0], types = 2 <= arguments.length ? __slice.call(arguments, 1) : [];
      this.id = uuid();
      if (typeof config === 'string') {
        config = {
          name: config,
          types: types
        };
      }
      if (!(config.name != null) || typeof config.name !== 'string' || config.name === '') {
        throw new Error("Argument is missing: 'name'");
      }
      if (config.name.match(/[\.#*]/)) {
        throw new Error('Invalid character in name. The following are reserved: .#*');
      }
      this.name = config.name;
      if ((!(config.types != null)) || (!config.types instanceof Array) || (config.types.length === 0)) {
        this.types = ['number'];
      } else {
        this.types = config.types;
      }
      this.enabled = config.enabled === true;
      this.instant = config.instant === true;
      this.sampleThreshold = !(config.sampleThreshold != null) ? SAMPLE_THRESHOLD : config.sampleThreshold;
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
      this.consumerIds = [];
      this.consumerTimers = {};
      this.disableDelay = new Delay;
      this.hits = 0;
    }

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
        var consumerIds, sample;
        sample = {
          timestamp: ts || Date.now(),
          hits: _this.hits,
          args: v,
          error: err
        };
        consumerIds = consumerId != null ? [consumerId] : _this.consumerIds;
        _this.emit('sample', sample, consumerIds);
        if (callback != null) return callback(null, sample, consumerIds);
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

    Probe.prototype.setEnabled = function(enabled) {
      var consumerId, timer, _ref;
      this.enabled = enabled;
      if (!enabled) {
        _ref = this.consumerTimers;
        for (consumerId in _ref) {
          timer = _ref[consumerId];
          timer.stop();
        }
        this.consumerTimers = {};
        return this.consumerIds = [];
      }
    };

    Probe.prototype.enableForConsumer = function(consumerId, interval, probeKey) {
      var newConsumerId,
        _this = this;
      if (this.instant) {
        newConsumerId = -1 === this.consumerIds.indexOf(consumerId);
        if (newConsumerId) this.consumerIds.push(consumerId);
      } else {
        newConsumerId = !this.consumerTimers.hasOwnProperty(consumerId);
        if (newConsumerId) this.sampleByInterval(consumerId, interval);
      }
      this.enabled = true;
      return this.disableDelay.start(PROBE_DISABLE_DELAY, function() {
        console.log('disable', probeKey);
        return _this.setEnabled(false);
      });
    };

    Probe.prototype.sampleByInterval = function(consumerId, interval) {
      var timer,
        _this = this;
      if (interval === 0) return;
      timer = this.consumerTimers[consumerId];
      if (!(timer != null)) {
        timer = new Timer;
        this.consumerTimers[consumerId] = timer;
      }
      return timer.start(interval, function() {
        return _this.sample(consumerId);
      });
    };

    Probe.prototype.stop = function(consumerId) {
      var index, timer;
      index = this.consumerIds.indexOf(consumerId);
      if (index !== -1) this.consumerIds.splice(index, 1);
      timer = this.consumerTimers[consumerId];
      if (timer != null) {
        timer.stop();
        return delete this.consumerTimers[consumerId];
      }
    };

    return Probe;

  })(EventEmitter);

}).call(this);
