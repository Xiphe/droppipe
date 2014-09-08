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


incrementor = (value, done) ->
  done null, value + 1

decrementor = (value, done) ->
  done null, value - 1

class Pipeline
  constructor: (config) ->
    @pipes = config.pipes
    @logger = config.logger || console
    @database = config.database
    @dropboxClient = config.dropboxClient
    @jobFailureAttempts = config.jobFailureAttempts || 5
    @jobs = kue.createQueue()
    @jobTimeout = 1000 * (if typeof config.jobTimeout == 'number' then config.jobTimeout else 60)
    @queuedJobs = 0

  start: ->
    @jobs.process CONSTANTS.FILE_PROCESSOR_JOB_ID, @_preprocessor
    @logger.log "Job processor started."

  addJob: (data, attempts = @jobFailureAttempts) ->
    Q.invoke @jobs, 'create', CONSTANTS.FILE_PROCESSOR_JOB_ID, data
      .then (job) => job.attempts(attempts)
      .then (job) => job.save()
      .then (job) => job.on('complete', @_jobDone).on 'failed', @_jobDone
      .then => Q.ninvoke @database, 'update', CONSTANTS.ACTIVE_JOBS_KEY, 0, incrementor
      .then => @logger.log "Created job"
      .catch (err) =>
        @_error "Failed to create job - #{err}"
        throw err

  _error: (err) =>
    @logger.error err
    @pipes.error? err

  _preprocessor: (job, done) =>
    change = job.data.change

    processingPromise = @_process change
    processingPromise.catch (err) =>
      @_error "Error while processing job('#{change.path}'): #{err}"
    processingPromise.then =>
      @logger.log "Finished processing job('#{change.path}')"

    processingPromise.nodeify done
    return processingPromise

  _toGulpFileStream: (change) =>
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

  _process: (change) =>
    changePath = change.path
    relativePath = changePath.replace /^\//, ''
    direction = if change.wasRemoved then CONSTANTS.PIPE_OUT else CONSTANTS.PIPE_IN

    return Q.when true if direction == CONSTANTS.PIPE_IN && change.stat.is_dir

    @logger.log "Start processing '#{relativePath}' -> #{direction}."

    pipe = false
    pipeMatcher = null

    for match, p of @pipes[direction]
      if !pipe && minimatch relativePath, match
        pipeMatcher = match
        pipe = p

    if pipe
      Q.fcall => if direction == CONSTANTS.PIPE_IN then @_toGulpFileStream change else relativePath
        .then (change) =>
          d = Q.defer()
          pipeDone = false
          @logger.log "Pipe '#{changePath}' #{if direction == CONSTANTS.PIPE_IN then 'into' else 'out of'} '#{pipeMatcher}'."

          Q.nfcall pipe, change
            .then d.resolve, d.reject

          d.promise.finally -> pipeDone = true

          if @jobTimeout > 0
            setTimeout =>
              unless pipeDone
                d.reject new Error "Pipe '#{changePath}' timed out after #{@jobTimeout / 1000} seconds."
            , @jobTimeout

          return d.promise

    else
      @logger.warn "No pipes found for '#{change.path}'."
      Q.when true

  _jobDone: =>
    Q.ninvoke @database, 'update', CONSTANTS.ACTIVE_JOBS_KEY, decrementor
      .then (activeJobs) => @pipes.done?() if activeJobs == 0

Pipeline.CONSTANTS = CONSTANTS
module.exports = Pipeline
