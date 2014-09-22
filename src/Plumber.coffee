Q = require 'q'

### @const ###
PREFIX = 'droppipe-plumber-'

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
    startPromise = Q.ninvoke(@database, 'get', CONSTANTS.CURSOR_TAG_KEY, false).then (cursorTag) =>
      deltaOptions = if cursorTag then cursorTag: cursorTag else null

      Q.ninvoke(@dropboxClient, 'delta', deltaOptions).then (data) =>
        @getDeletedMeta(data.changes)
          .then (changes) => @queueFileChanges(changes)
          .then => @saveCursorTag data.cursorTag
          .then => if data.shouldPullAgain then @start()

    startPromise.nodeify done if done
    return startPromise

  saveCursorTag: (cursorTag) =>
    Q.ninvoke(@database, 'set', CONSTANTS.CURSOR_TAG_KEY, cursorTag)
      .then => @logger.log 'saved cursorTag.'

  getDeletedMeta: (changes) ->
    d = Q.defer()
    unless changes?.length
      return Q.when(changes)

    queue = []

    changes.forEach (change) =>
      unless change.stat
        queue.push Q.ninvoke(@dropboxClient, 'metadata', change.path).then (data) =>
          change.stat = data[0];

    Q.all(queue)
      .then -> d.resolve(changes);
      .catch d.reject

    return d.promise;

  queueFileChanges: (changes) ->
    unless changes?.length
      @logger.log "no delta changes."
      return Q.all []

    queue = []
    doneQueue = []

    changes.forEach (change) =>
      promise = @pipeline.addJob(change: change)
      queue.push promise
      promise.then (job) ->
        doneQueue.push job.done

    return Q.all(queue).then =>
      Q.all(doneQueue).then =>
        @logger.log('ALL JOBS DONE, CALLING DONE')
        @pipeline.callDone()
          .then => @logger.log('DONE CALLBACK IS DONE :)')
      .catch (err) =>
        @pipeline._error(err)

      @logger.log('ALL JOBS ADDED')


Plumber.CONSTANTS = CONSTANTS
module.exports = Plumber
