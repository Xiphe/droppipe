taskman = require 'node-taskman'
minimatch = require 'minimatch'
stream = require 'stream'
gutil = require "gulp-util"
Q = require 'q'

### @const ###
PREFIX = 'dropbox-plumber-'

### @const ###
CONSTANTS =
  FILE_PROCESSOR_WORKER_ID: PREFIX + 'file-processor'
  PIPE_IN: 'in'
  PIPE_OUT: 'out'

class Pipeline
  constructor: (config = {}) ->
    @pipes = config.pipes
    @logger = config.logger || console
    @dropboxClient = config.dropboxClient
    @queue = taskman.createQueue CONSTANTS.FILE_PROCESSOR_WORKER_ID

  start: ->
    worker = taskman.createWorker CONSTANTS.FILE_PROCESSOR_WORKER_ID
    worker.process @preprocessor
    @logger.log "Worker started."

  preprocessor: (changeObjs, done) =>
    queue = []

    changeObjs.forEach (changeObj) =>
      change = changeObj.change

      processingPromise = @process change
      processingPromise.catch (err) =>
        @logger.error "Error while processing #{change.path}: #{err}"
      processingPromise.then =>
        @logger.log "Finished processing #{change.path}"

      queue.push processingPromise

    processingPromise = Q.all queue
    processingPromise.nodeify done
    return processingPromise

  toGulpFileStream: (change) =>
    Q.ninvoke @dropboxClient, 'readFile', change.path, buffer: true
      .then (result) ->
        meta = result[1]
        contents = result[0]
        return new gutil.File cwd: '', base: '', path: ".#{meta.path}", contents: contents

      .then (gulpFile) ->
        src = stream.Readable objectMode: true
        src._read = ->
          @push gulpFile
          @push null

        return src

  process: (change) =>
    relativePath = change.path.replace /^\//, ''
    direction = if change.wasRemoved then CONSTANTS.PIPE_OUT else CONSTANTS.PIPE_IN
    @logger.log "Processing '#{relativePath}' -> #{direction}."

    pipe = false
    pipeMatcher = null

    for match, p of @pipes[direction]
      if !pipe && minimatch relativePath, match
        pipeMatcher = match
        pipe = p

    if pipe
      @logger.log "piping '#{change.path}' #{if CONSTANTS.PIPE_IN then 'into' else 'out of'} '#{pipeMatcher}'."
      Q.fcall => if direction == CONSTANTS.PIPE_IN then @toGulpFileStream change else relativePath
        .then (change) => Q.nfcall pipe, change
    else
      @logger.log "No pipes found for '#{change.path}'."
      Q.when true


Pipeline.CONSTANTS = CONSTANTS
module.exports = Pipeline
