taskman = require 'node-taskman'
Q = require 'q'

### @const ###
PREFIX = 'dropbox-plumber-'

### @const ###
CONSTANTS =
  FILE_PROCESSOR_WORKER_ID: PREFIX + 'file-processor'

class Pipeline
  constructor: (config = {}) ->
    @pipes = config.pipes
    @logger = config.logger || console
    @queue = taskman.createQueue CONSTANTS.FILE_PROCESSOR_WORKER_ID

  start: ->
    worker = taskman.createWorker CONSTANTS.FILE_PROCESSOR_WORKER_ID
    worker.process @preprocessor
    @logger.log "Worker started."

  preprocessor: (changes, done) =>
    queue = []

    changes.forEach (change) =>
      queue.push @process change.change

    processingPromise = Q.all queue
    processingPromise.nodeify done
    return processingPromise

  process: (change) =>
    @logger.log "Processing '#{change.path}'."


Pipeline.CONSTANTS = CONSTANTS
module.exports = Pipeline