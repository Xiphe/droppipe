kue = require 'kue'
minimatch = require 'minimatch'
stream = require 'stream'
gutil = require "gulp-util"
Q = require 'q'

### @const ###
PREFIX = 'dropbox-plumber-'

### @const ###
CONSTANTS =
  FILE_PROCESSOR_JOB_ID: PREFIX + 'file-processor'
  PIPE_IN: 'in'
  PIPE_OUT: 'out'

class Pipeline
  constructor: (config = {}) ->
    @pipes = config.pipes
    @logger = config.logger || console
    @dropboxClient = config.dropboxClient
    @jobFailureAttempts = config.jobFailureAttempts || 5
    @jobs = kue.createQueue()
    @queuedJobs = 0

  start: ->
    @jobs.process CONSTANTS.FILE_PROCESSOR_JOB_ID, @preprocessor
    @logger.log "Job processor started."

  addJob: (data) ->
    job = @jobs.create(CONSTANTS.FILE_PROCESSOR_JOB_ID, data).attempts(@jobFailureAttempts).save (err) =>
      return @logger.error "Failed to create job##{job.id} - #{err}" if err
      @logger.log "Created job##{job.id}"
      @queuedJobs += 1


  preprocessor: (job, done) =>
    change = job.data.change

    processingPromise = @process change
    processingPromise.catch (err) =>
      @logger.error "Error while processing job##{job.id}('#{change.path}'): #{err}"
    processingPromise.then =>
      @logger.log "Finished processing job##{job.id}('#{change.path}')"

    processingPromise.nodeify done
    return processingPromise

  toGulpFileStream: (change) =>
    @logger.log "Fetch '#{change.path}' from dropbox."
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
    changePath = change.path
    relativePath = changePath.replace /^\//, ''
    direction = if change.wasRemoved then CONSTANTS.PIPE_OUT else CONSTANTS.PIPE_IN
    @logger.log "Start processing '#{relativePath}' -> #{direction}."

    pipe = false
    pipeMatcher = null

    for match, p of @pipes[direction]
      if !pipe && minimatch relativePath, match
        pipeMatcher = match
        pipe = p

    if pipe
      Q.fcall => if direction == CONSTANTS.PIPE_IN then @toGulpFileStream change else relativePath
        .then (change) =>
          @logger.log "Pipe '#{changePath}' #{if CONSTANTS.PIPE_IN then 'into' else 'out of'} '#{pipeMatcher}'."
          Q.nfcall pipe, change
    else
      @logger.warn "No pipes found for '#{change.path}'."
      Q.when true


Pipeline.CONSTANTS = CONSTANTS
module.exports = Pipeline
