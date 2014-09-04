kue = require 'kue'
minimatch = require 'minimatch'
stream = require 'stream'
gutil = require "gulp-util"
Q = require 'q'

### @const ###
PREFIX = 'dropbox-plumber-'

### @const ###
CONSTANTS =
  ACTIVE_JOBS_KEY: PREFIX + 'active-jobs'
  FILE_PROCESSOR_JOB_ID: PREFIX + 'file-processor'
  PIPE_IN: 'in'
  PIPE_OUT: 'out'

class Pipeline
  constructor: (config = {}) ->
    @pipes = config.pipes
    @logger = config.logger || console
    @database = config.database
    @dropboxClient = config.dropboxClient
    @jobFailureAttempts = config.jobFailureAttempts || 5
    @jobs = kue.createQueue()
    @queuedJobs = 0

  start: ->
    @jobs.process CONSTANTS.FILE_PROCESSOR_JOB_ID, @preprocessor
    @logger.log "Job processor started."

  addJob: (data, attempts = @jobFailureAttempts) ->
    job = null

    Q.invoke @jobs, 'create', CONSTANTS.FILE_PROCESSOR_JOB_ID, data
      .then (_job) => job = _job; job.attempts(attempts)
      .then => job.save()
      .then => Q.ninvoke @database, 'get', CONSTANTS.ACTIVE_JOBS_KEY, true
      .then (activeJobs) => Q.ninvoke @database, 'set', CONSTANTS.ACTIVE_JOBS_KEY, activeJobs + 1
      .then => @logger.log "Created job##{job.id}"
      .catch (err) => @logger.error "Failed to create job##{job?.id} - #{err}"


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
