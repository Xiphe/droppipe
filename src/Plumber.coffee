Q = require 'q'

### @const ###
PREFIX = 'dropbox-plumber-'

### @const ###
CONSTANTS =
  CURSOR_TAG_KEY: PREFIX + 'cursor-tag'

class Plumber
  constructor: (config) ->
    @dropboxClient = config.dropboxClient
    @database = config.database
    @logger = config.logger || console
    @pipeline = config.pipeline

  start: (done) ->
    startPromise = Q.ninvoke(@database, 'get', CONSTANTS.CURSOR_TAG_KEY, true).then (cursorTag) =>
      deltaOptions = if cursorTag then cursorTag: cursorTag else null

      Q.ninvoke(@dropboxClient, 'delta', deltaOptions).then (data) =>
        @saveCursorTag(data.cursorTag)
          .then => @queueFileChanges data.changes
          .then => if data.shouldPullAgain then @start()

    startPromise.nodeify done if done
    return startPromise

  saveCursorTag: (cursorTag) =>
    Q.ninvoke(@database, 'set', CONSTANTS.CURSOR_TAG_KEY, cursorTag)
      .then => @logger.log 'saved cursorTag.'

  queueFileChanges: (changes) ->
    unless changes?.length
      return  @logger.log "no delta changes."

    changes.forEach (change) =>
      @pipeline.queue.push change: change, dropboxCredentials: @dropboxClient.credentials()
      @logger.log "Queued #{if change.wasRemoved then 'removing' else 'update'} of '#{change.path}'."

Plumber.CONSTANTS = CONSTANTS
module.exports = Plumber
