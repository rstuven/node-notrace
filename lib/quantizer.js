// Generated by CoffeeScript 1.9.2

/**
 * A frequency distribution of the values.
 * Increments the count in the highest bucket that is lower than the value.
 */

(function() {
  var LinearQuantizer, Pow2Quantizer, Quantizer,
    extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

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
      if (index == null) {
        return;
      }
      this.prepare(index);
      count = ++this.counts[index - this.minIndex];
      if (this.maxCount < count) {
        return this.maxCount = count;
      }
    };

    Quantizer.prototype.prepare = function(index) {
      var i, j, k, maxIndex, maxSince, minIndex, minUntil, ref, ref1, ref2, ref3;
      if (index < this.maxIndex && index > this.minIndex) {
        return;
      }
      minIndex = Math.min(index - 1, this.minIndex);
      maxIndex = Math.max(index + 1, this.maxIndex);
      minUntil = this.minIndex === +Infinity ? minIndex : this.minIndex - 1;
      for (i = j = ref = minIndex, ref1 = minUntil; j <= ref1; i = j += 1) {
        this.counts.unshift(0);
      }
      maxSince = this.maxIndex === -Infinity ? maxIndex - 1 : this.maxIndex + 1;
      for (i = k = ref2 = maxSince, ref3 = maxIndex; k <= ref3; i = k += 1) {
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

  exports.Pow2Quantizer = Pow2Quantizer = (function(superClass) {
    extend(Pow2Quantizer, superClass);

    function Pow2Quantizer() {
      return Pow2Quantizer.__super__.constructor.apply(this, arguments);
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

  exports.LinearQuantizer = LinearQuantizer = (function(superClass) {
    extend(LinearQuantizer, superClass);

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
      this.prepare(this.valueIndex(this.lowerBound));
      this.prepare(this.valueIndex(this.upperBound));
    }

    LinearQuantizer.prototype.indexValue = function(index) {
      return this.lowerBound + index * this.stepValue;
    };

    LinearQuantizer.prototype.valueIndex = function(value) {
      if (value < this.lowerBound) {
        return null;
      }
      if (value > this.upperBound) {
        return null;
      }
      return Math.ceil((value - this.lowerBound) / this.stepValue);
    };

    return LinearQuantizer;

  })(Quantizer);

}).call(this);
