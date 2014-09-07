describe 'Pipeline', ->
  proxyquire = require 'proxyquire'
  _ = require 'lodash'
  Q = require 'q'
  idkeyvalue = require 'idkeyvalue'
  kueStub = {}
  Pipeline = proxyquire '../src/Pipeline', 'kue': kueStub

  fakeLogger = null
  fakeJobs = null
  database = null
  job = null
  jobs = null
  databaseAdapter = null
  fakeJobCount = 0

  fakeJobFactory = ->
    job =
      events: {}
      id: fakeJobCount++
      attempts: -> job
      save: (done) -> done?(); return job
      on: (key, callback) -> this.events[key] = callback; return job

    jobs.push job

    return job

  pipelineFactory = (customConfig = {}) ->
    defaults =
      logger: fakeLogger
      database: databaseAdapter
      dropboxClient: {}

    config = _.merge defaults, customConfig
    new Pipeline config

  beforeEach ->
    job = null
    jobs = []
    fakeJobCount = 1

    fakeLogger =
      log: ->
      warn: ->
      error: ->

    fakeJobs =
      create: fakeJobFactory
      process: ->

    kueStub.createQueue = -> fakeJobs

    database = {}
    databaseAdapter = new idkeyvalue.ObjectAdapter database

  it 'should exist', ->
    pipelineFactory().should.exist

  describe 'start', ->
    it 'should start a taskman worker and register the preprocessor', ->
      sinon.spy kueStub, 'createQueue'
      sinon.spy fakeJobs, 'process'
      pipeline = pipelineFactory()
      pipeline.start()

      kueStub.createQueue.should.have.been.calledOnce
      fakeJobs.process.should.have.been.calledOnce
      fakeJobs.process.should.have.been.calledWith Pipeline.CONSTANTS.FILE_PROCESSOR_JOB_ID, pipeline._preprocessor

  describe 'addJob', ->
    it 'should add jobs to a queue', (done) ->
      sinon.spy fakeJobs, 'create'
      myData = foo: 'bar'

      pipelineFactory().addJob(myData).finally ->
        fakeJobs.create.should.have.been.calledOnce
        fakeJobs.create.should.have.been.calledWith Pipeline.CONSTANTS.FILE_PROCESSOR_JOB_ID, myData
        done()

    it 'should update the active job count in database', (done) ->
      myPreviousCount = 7
      sinon.stub(databaseAdapter, 'get').callsArgWithAsync 2, null, myPreviousCount
      sinon.spy(databaseAdapter, 'set')
      myData = foo: 'bar'

      pipelineFactory().addJob(myData).then ->
        databaseAdapter.get.should.have.been.calledOnce
        databaseAdapter.set.should.have.been.calledOnce
        databaseAdapter.get.should.have.been.calledWith Pipeline.CONSTANTS.ACTIVE_JOBS_KEY
        databaseAdapter.set.should.have.been.calledWith Pipeline.CONSTANTS.ACTIVE_JOBS_KEY, myPreviousCount + 1
        done()
      .catch done

    it 'should log errors occurred during job creation', (done) ->
      myError = new Error 'Lorem Ipsum'
      myData = foo: 'bar'
      sinon.stub(fakeJobs, 'create').throws myError
      sinon.spy(fakeLogger, 'error')
      error = null

      pipeline = pipelineFactory()

      pipeline.addJob(myData).catch (err) ->
        myError.should.equal err
        fakeLogger.error.should.have.been.calledOnce
        done()
        throw err
      .then -> done new Error "promise resolved"
      .catch (err) -> done err unless err == myError


  describe '_preprocessor', ->
    it 'should pass changes to _process', (done) ->
      pipeline = pipelineFactory()
      sinon.stub(pipeline, '_process').returns Q.when true

      fakeJob = data: change: 'hello'

      pipeline._preprocessor fakeJob, (err) ->
        return done(err) if err
        pipeline._process.should.have.been.calledOnce
        pipeline._process.getCall(0).args[0].should.equal fakeJob.data.change
        done()

    it 'should notify the done pipes when finished', (done) ->
      pipes =
        done: sinon.spy()

      pipeline = pipelineFactory pipes: pipes
      sinon.stub(pipeline, '_process').returns Q.when true

      pipeline.addJob change: 'hello'
        .then ->
          job.events.complete()
          setTimeout ->
            pipes.done.should.have.been.called
            done()
          , 0
        .catch done

    it 'should not notify the done pipes when not finished', (done) ->
      pipes =
        done: sinon.spy()

      pipeline = pipelineFactory pipes: pipes
      sinon.stub(pipeline, '_process').returns Q.when true

      pipeline.addJob change: 'hello'
        .then ->
          pipeline.addJob change: 'world'
            .then ->
              job.events.complete()
              setTimeout ->
                pipes.done.should.not.have.been.called
                done()
              , 1
        .catch done


  describe '_process', ->
    inPipeStub = null
    outPipeStub = null
    pipeline = null

    beforeEach ->
      pipeline = null
      inPipeStub = sinon.stub().callsArgWithAsync 1, null
      outPipeStub  = sinon.stub().callsArgWithAsync 1, null

    process = (change, pipes = null) ->
      unless pipes
        pipes =
          in: '**': inPipeStub
          out: '**': outPipeStub

      pipeline = pipelineFactory pipes: pipes
      sinon.stub(pipeline, '_toGulpFileStream').returns true
      sinon.stub(databaseAdapter, 'get').callsArgWithAsync 1, null, 99

      return pipeline._process change

    it 'should put new changes the the in pipes', (done) ->
      process(path: '/foo.bar', stat: {}).then ->
        inPipeStub.should.have.been.calledOnce
        done()
      .catch done

    it 'should put removed changes to the out pipe', (done) ->
      relativeFile = 'boo.far'
      process(path: "/#{relativeFile}", wasRemoved: true, stat: {}).then ->
        outPipeStub.should.have.been.calledOnce
        outPipeStub.should.have.been.calledWith relativeFile
        done()
      .catch done

    it 'should not process unmatched files', (done) ->
      coffeeSpy = sinon.spy()
      pipes =
        in: '*.coffee': coffeeSpy

      process({path: '/asdf.js', stat: {}}, pipes).then ->
        coffeeSpy.should.not.have.been.called
        done()
      .catch done

    it 'should transform changes to gulp files', (done) ->
      myChange = path: '/foo.bar', stat: {}
      process(myChange).then ->
        pipeline._toGulpFileStream.should.have.been.calledOnce
        pipeline._toGulpFileStream.should.have.been.calledWith myChange
        done()
      .catch done

    it 'should not transform out-changes to gulp files', (done) ->
      process(path: '/boo.far', wasRemoved: true, stat: {}).then ->
        pipeline._toGulpFileStream.should.not.have.been.calledOnce
        done()
      .catch done

    it 'should not process folders', (done) ->
      myChange =
        path: '/foo/bar'
        stat: is_dir: true

      process(myChange).then ->
        pipeline._toGulpFileStream.should.not.have.been.called
        done()
      .catch done

  describe '_toGulpFileStream', ->
    dropboxClient = null
    readFileStub = null

    beforeEach ->
      myContent = new Buffer 'Lorem Ipsum', 'utf-8'
      readFileStub = sinon.stub().callsArgWithAsync 2, null, [myContent, path: '/foo.bar']

      dropboxClient =
        readFile: readFileStub

      sinon.stub(databaseAdapter, 'get').callsArgWithAsync 1, null, 99

    it 'should request the files content from dropbox', (done) ->
      myChange = path: '/foo.bar', stat: {}

      pipelineFactory(dropboxClient: dropboxClient)._toGulpFileStream(myChange).then ->
        readFileStub.should.have.been.called
        done()
      .catch done

    it 'should convert the dropbox response to a gulp file stream', (done) ->
      inPipeStub = sinon.stub().callsArgWithAsync 1, null
      pipes =
        in: '**': inPipeStub

      pipelineFactory(dropboxClient: dropboxClient, pipes: pipes)._process(path: '/foo.bar', stat: {}).then ->
        inPipeStub.should.have.been.called
        inPipeStub.getCall(0).args[0].pipe.should.be.an.instanceof Function
        done()
      .catch done
