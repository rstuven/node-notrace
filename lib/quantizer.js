(function() {
  var Quantizer;

  exports.Quantizer = Quantizer = (function() {

    function Quantizer() {
      this.counts = [];
      this.minIndex = Infinity;
      this.maxIndex = -Infinity;
      this.maxCount = 0;
    }

    Quantizer.prototype.add = (function() {
      var log2;
      log2 = Math.log(2);
      return function(value) {
        var count, index;
        index = this.unsign(value, 0, function(x) {
          return 1 + Math.floor(Math.log(x) / log2);
        });
        this.prepare(index);
        count = ++this.counts[index - this.minIndex];
        if (this.maxCount < count) return this.maxCount = count;
      };
    })();

    Quantizer.prototype.unsign = function(x, n, fn) {
      if (x === 0) {
        return 0;
      } else if (x < 0) {
        return -fn(-x - n);
      } else {
        return fn(x - n);
      }
    };

    Quantizer.prototype.prepare = function(index) {
      var i, maxIndex, maxSince, minIndex, minUntil;
      if (index < this.maxIndex && index > this.minIndex) return;
      minIndex = Math.min(index - 1, this.minIndex);
      maxIndex = Math.max(index + 1, this.maxIndex);
      minUntil = this.minIndex === +Infinity ? minIndex : this.minIndex - 1;
      for (i = minIndex; i <= minUntil; i += 1) {
        this.counts.unshift(0);
      }
      maxSince = this.maxIndex === -Infinity ? maxIndex - 1 : this.maxIndex + 1;
      for (i = maxSince; i <= maxIndex; i += 1) {
        this.counts.push(0);
      }
      this.minIndex = minIndex;
      return this.maxIndex = maxIndex;
    };

    Quantizer.prototype.indexValue = function(index) {
      return this.unsign(index, 1, (function(x) {
        return Math.pow(2, x);
      }));
    };

    Quantizer.prototype.count = function(index) {
      return this.counts[index - this.minIndex];
    };

    return Quantizer;

  })();

}).call(this);
