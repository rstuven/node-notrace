# exchange to publish samples
exports.samples = (connection, callback) ->
    return if not connection?
    connection.exchange 'notrace-samples',
        type: 'topic'
        autoDelete: true
        callback

# exchange to publish requests
exports.requests = (connection, callback) ->
    return if not connection?
    connection.exchange 'notrace-requests',
        type: 'fanout'
        autoDelete: true
        callback
