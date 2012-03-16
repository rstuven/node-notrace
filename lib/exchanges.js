(function() {

  exports.samples = function(connection, callback) {
    if (!(connection != null)) return;
    return connection.exchange('notrace-samples', {
      type: 'topic',
      autoDelete: true
    }, callback);
  };

  exports.requests = function(connection, callback) {
    if (!(connection != null)) return;
    return connection.exchange('notrace-requests', {
      type: 'fanout',
      autoDelete: true
    }, callback);
  };

}).call(this);
