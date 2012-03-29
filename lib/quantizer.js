
/**
 * A frequency distribution of the values.
 * Increments the count in the highest bucket that is less than the value.
*/

(function() {
  var LinearQuantizer, Pow2Quantizer, Quantizer,
    __hasProp = Object.prototype.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor; child.__super__ = parent.prototype; return child; };

  exports.Quantizer = Quantizer = (function() {

    function Quantizer() {
      this.counts = [];
      this.minIndex = Infinity;
      this.maxIndex = -Infinity;
      this.maxCount = 0;
    }

    Quantizer.prototype.add = function(value) {
      var count, index;
      index = this.valueIndex(value);
      if (!(index != null)) return;
      this.prepare(index);
      count = ++this.counts[index - this.minIndex];
      if (this.maxCount < count) return this.maxCount = count;
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

    Quantizer.prototype.count = function(index) {
      return this.counts[index - this.minIndex];
    };

    Quantizer.prototype.indexValue = function(index) {
      throw new Error('Method not implemented.');
    };

    Quantizer.prototype.valueIndex = function(value) {
      throw new Error('Method not implemented.');
    };

    return Quantizer;

  })();

  /**
   * A power-of-two frequency distribution of the values.
   * Increments the count in the highest power-of-two bucket that is less than the value.
  */

  exports.Pow2Quantizer = Pow2Quantizer = (function(_super) {

    __extends(Pow2Quantizer, _super);

    function Pow2Quantizer() {
      Pow2Quantizer.__super__.constructor.apply(this, arguments);
    }

    Pow2Quantizer.prototype.indexValue = function(index) {
      return this.unsign(index, 1, (function(x) {
        return Math.pow(2, x);
      }));
    };

    Pow2Quantizer.prototype.valueIndex = (function() {
      var log2;
      log2 = Math.log(2);
      return function(value) {
        return this.unsign(value, 0, function(x) {
          return 1 + Math.floor(Math.log(x) / log2);
        });
      };
    })();

    Pow2Quantizer.prototype.unsign = function(x, n, fn) {
      if (x === 0) {
        return 0;
      } else if (x < 0) {
        return -fn(-x - n);
      } else {
        return fn(x - n);
      }
    };

    return Pow2Quantizer;

  })(Quantizer);

  /**
   * A linear frequency distribution of values between the specified bounds.
   * Increments the count in the highest bucket that is less than the value.
  */

  exports.LinearQuantizer = LinearQuantizer = (function(_super) {

    __extends(LinearQuantizer, _super);

    function LinearQuantizer(lowerBound, upperBound, stepValue) {
      this.lowerBound = lowerBound;
      this.upperBound = upperBound;
      this.stepValue = stepValue;
      if (this.stepValue <= 0) {
        throw new Error('stepValue must be greater than 0.');
      }
      if (this.upperBound <= this.lowerBound) {
        throw new Error('upperBound must be greater than lowerBound.');
      }
      LinearQuantizer.__super__.constructor.call(this);
    }

    LinearQuantizer.prototype.indexValue = function(index) {
      return this.lowerBound + index * this.stepValue;
    };

    LinearQuantizer.prototype.valueIndex = function(value) {
      if (value < this.lowerBound) return null;
      if (value > this.upperBound) return null;
      return Math.ceil((value - this.lowerBound) / this.stepValue);
    };

    return LinearQuantizer;

  })(Quantizer);

}).call(this);