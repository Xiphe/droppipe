taskman = require 'node-taskman'
Q = require 'q'

### @const ###
PREFIX = 'dropbox-plumber-'

### @const ###
CONSTANTS =
  CURSOR_TAG_KEY: PREFIX + 'cursor-tag'
  FILE_PROCESSOR_WORKER_ID: PREFIX + 'file-processor'

class Plumber
  constructor: (config) ->
    @dropboxClient = config.dropboxClient
    @database = config.database
    @log = config.logger || console

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
      .then => @log.log 'saved cursorTag.'

  queueFileChanges: (changes) ->
    unless changes?.length
      return  @log.log "no delta changes."

    queue = taskman.createQueue CONSTANTS.FILE_PROCESSOR_WORKER_ID
    changes.forEach (change) =>
      queue.push change: change
      @log.log "Queued #{if change.wasRemoved then 'removing' else 'update'} of '#{change.path}'."

Plumber.startworker = ->
  worker = taskman.createWorker CONSTANTS.FILE_PROCESSOR_WORKER_ID
  worker.process (files, done) ->
    # Process files here!
    done()

  console.log 'taskman worker started.'

Plumber.CONSTANTS = CONSTANTS
module.exports = Plumber
