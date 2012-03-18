(function() {
  var Delay, Timer;

  exports.Timer = Timer = (function() {

    function Timer() {}

    Timer.prototype.start = function(interval, fn) {
      this.stop();
      return this.id = setInterval(fn, interval);
    };

    Timer.prototype.stop = function() {
      if (this.id != null) {
        clearInterval(this.id);
        return this.id = null;
      }
    };

    Timer.prototype.isStarted = function() {
      return this.id != null;
    };

    return Timer;

  })();

  exports.Delay = Delay = (function() {

    function Delay() {}

    Delay.prototype.start = function(delay, fn) {
      this.stop();
      return this.id = setTimeout(fn, delay);
    };

    Delay.prototype.stop = function() {
      if (this.id != null) {
        clearTimeout(this.id);
        return this.id = null;
      }
    };

    Delay.prototype.isStarted = function() {
      return this.id != null;
    };

    return Delay;

  })();

}).call(this);
