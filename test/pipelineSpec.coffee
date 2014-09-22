describe 'Pipeline', ->
  Q = require 'q'
  kueStub = null
  pipelineFactory = require './mocks/pipeline'

  getFakeJobs = ->
    fakeJobs = kueStub.createQueue()
    sinon.stub(kueStub, 'createQueue').returns fakeJobs

    return fakeJobs

  beforeEach ->
    kueStub = pipelineFactory.kueStub

  it 'should exist', ->
    pipelineFactory().should.exist

  it 'should use console as default logger', ->
    sinon.spy console, 'log'

    pipeline = pipelineFactory database: pipelineFactory.databaseAdapter(), dropboxClient: {}, true
    pipeline.logger.log 'Hello'

    console.log.should.have.been.calledWith 'Hello'

  it 'should pass configuration to kue', ->
    sinon.spy kueStub, 'createQueue'
    myKueConfig = hello: 'Kue'
    pipelineFactory kueConfig: myKueConfig

    kueStub.createQueue.should.have.been.calledOnce
    kueStub.createQueue.should.have.been.calledWith myKueConfig

  describe 'start', ->
    it 'should start a kue worker and register the preprocessor', ->
      fakeJobs = getFakeJobs()
      sinon.spy fakeJobs, 'process'
      pipeline = pipelineFactory()
      pipeline.start()

      kueStub.createQueue.should.have.been.calledOnce
      fakeJobs.process.should.have.been.calledOnce
      fakeJobs.process.should.have.been.calledWith pipelineFactory.CONSTANTS.FILE_PROCESSOR_JOB_ID, pipeline._preprocessor

  describe 'addJob', ->
    fakeJobs = null
    myData = null

    beforeEach ->
      fakeJobs = getFakeJobs()
      myData = change: path: 'bar', stat: path: 'bar'

    it 'should add jobs to a queue', (done) ->
      sinon.spy fakeJobs, 'create'

      pipelineFactory().addJob(myData).then ->
        fakeJobs.create.should.have.been.calledOnce
        fakeJobs.create.should.have.been.calledWith pipelineFactory.CONSTANTS.FILE_PROCESSOR_JOB_ID, myData
        done()
      .catch done

    it 'should have customizable attempts', (done) ->
      oneAttempt = 1
      job = fakeJobs.create()
      sinon.spy job, 'attempts'
      sinon.stub(fakeJobs, 'create').returns job

      pipelineFactory().addJob(myData, oneAttempt).then ->
        job.attempts.should.have.been.calledOnce
        job.attempts.should.have.been.calledWith 1
        done()
      .catch done

    it 'should log errors occurred during job creation', (done) ->
      myError = new Error 'Lorem Ipsum'
      sinon.stub(fakeJobs, 'create').throws myError
      error = null

      pipeline = pipelineFactory(pipes: {})
      sinon.spy(pipeline.logger, 'error')

      pipeline.addJob(myData).catch (err) ->
        myError.should.equal err
        pipeline.logger.error.should.have.been.calledOnce
        done()
        throw err
      .then -> done new Error "promise resolved"
      .catch (err) -> done err unless err == myError

    it 'should pass errors to pipeline error callback', (done) ->
      myError = new Error 'Lorem Ipsum'
      sinon.stub(fakeJobs, 'create').throws myError
      error = null
      pipes = error: sinon.spy()

      pipeline = pipelineFactory(pipes: pipes)

      pipeline.addJob(myData).catch (err) ->
        pipes.error.should.have.been.calledOnce
        pipes.error.getCall(0).args[0].should.match /Lorem Ipsum/
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

    it 'should pass any error to done callback', (done) ->
      myError = new Error 'Fup'
      fakeProcessD = Q.defer()
      fakeProcessD.reject myError
      doneCalled = false

      pipeline = pipelineFactory()
      sinon.stub(pipeline, '_process').returns fakeProcessD.promise

      fakeJob = data: change: 'hello'

      preprocessorPromise = pipeline._preprocessor fakeJob, (err) ->
        myError.should.equal err
        doneCalled = true

      preprocessorPromise.catch (err) ->
        myError.should.equal err
        doneCalled.should.equal.true
        done()
        throw err
      .then -> done new Error "promise resolved"
      .catch (err) -> done err unless err == myError

  describe '_process', ->
    inPipeStub = null
    outPipeStub = null
    pipeline = null

    beforeEach ->
      pipeline = null
      inPipeStub = sinon.stub().callsArgWithAsync 1, null
      outPipeStub  = sinon.stub().callsArgWithAsync 1, null

    process = (change, pipes = null, timeout = 0.005) ->
      unless pipes
        pipes =
          in: '**': inPipeStub
          out: '**': outPipeStub

      pipeline = pipelineFactory pipes: pipes, jobTimeout: timeout
      sinon.stub(pipeline, '_toGulpFileStream').returns true

      return pipeline._process change

    it 'should put new changes the the in pipes', (done) ->
      process(path: '/foo.bar', stat: {path: '/foo.bar'}).then ->
        inPipeStub.should.have.been.calledOnce
        done()
      .catch done

    it 'should put removed changes to the out pipe', (done) ->
      relativeFile = 'boo.far'
      process(path: "/#{relativeFile}", wasRemoved: true, stat: {path: "/#{relativeFile}"}).then ->
        outPipeStub.should.have.been.calledOnce
        outPipeStub.should.have.been.calledWith relativeFile
        done()
      .catch done

    it 'should not process unmatched files', (done) ->
      coffeeSpy = sinon.spy()
      pipes =
        in: '*.coffee': coffeeSpy

      process({path: '/asdf.js', stat: {path: '/asdf.js'}}, pipes).then ->
        coffeeSpy.should.not.have.been.called
        done()
      .catch done

    it 'should transform changes to gulp files', (done) ->
      myChange = path: '/foo.bar', stat: {path: '/foo.bar'}
      process(myChange).then ->
        pipeline._toGulpFileStream.should.have.been.calledOnce
        pipeline._toGulpFileStream.should.have.been.calledWith myChange
        done()
      .catch done

    it 'should not transform out-changes to gulp files', (done) ->
      process(path: '/boo.far', wasRemoved: true, stat: {path: '/boo.far'}).then ->
        pipeline._toGulpFileStream.should.not.have.been.calledOnce
        done()
      .catch done

    it 'should not process folders', (done) ->
      myChange =
        path: '/foo/bar'
        stat: is_dir: true, path: '/foo/bar'

      process(myChange).then ->
        pipeline._toGulpFileStream.should.not.have.been.called
        done()
      .catch done

    it 'should time out if job is taking to long', (done) ->
      expectedErr = null
      pipes =
        in: '**': ->

      process({path: '/foo.bar', stat: {path: '/foo.bar'}}, pipes).catch (err) ->
        expectedErr = err
        err.message.should.contain 'timed out'
        done()
        throw err
      .then -> done new Error "promise resolved"
      .catch (err) -> done err unless err == expectedErr

    it 'should not time out if timeout is deactivated', (done) ->
      expectedErr = null
      pipes =
        in: '**': (change, done) -> setTimeout done, 6

      process({path: '/foo.bar', stat: {path: '/foo.bar'}}, pipes, 0).then done
      .catch done

  describe '_toGulpFileStream', ->
    dropboxClient = null
    readFileStub = null
    fakeContent = null

    beforeEach ->
      fakeContent = 'Lorem Ipsum'
      myContent = new Buffer fakeContent, 'utf8'
      readFileStub = sinon.stub().callsArgWithAsync 2, null, [myContent, path: '/foo.bar']

      dropboxClient =
        readFile: readFileStub

    it 'should request the files content from dropbox', (done) ->
      myChange = path: '/foo.bar', stat: {path: '/foo.bar'}

      pipelineFactory(dropboxClient: dropboxClient)._toGulpFileStream(myChange).then ->
        readFileStub.should.have.been.called
        done()
      .catch done

    it 'should convert the dropbox response to a gulp file stream', (done) ->
      inPipeStub = sinon.stub().callsArgWithAsync 1, null
      pipes =
        in: '**': inPipeStub

      pipelineFactory(dropboxClient: dropboxClient, pipes: pipes)._process(path: '/foo.bar', stat: {path: '/foo.bar'}).then ->
        inPipeStub.should.have.been.called
        inPipeStub.getCall(0).args[0].pipe.should.be.an.instanceof Function
        done()
      .catch done

    it 'should create a readable stream containing a gulp file', (done) ->
      myChange = path: '/foo.bar', stat: {path: '/foo.bar'}

      pipelineFactory(dropboxClient: dropboxClient)._toGulpFileStream(myChange).then (stream) ->
        bufs = []
        stream.on 'data', (d) -> bufs.push d
        stream.on 'end', ->
          buf = Buffer.concat bufs
          buf.contents.toString().should.equal fakeContent
          done()

      .catch done

  describe 'callDone', ->
    it 'should call piplines done callback if present', (done) ->
      pipes =
        done: (done) -> done()

      sinon.spy(pipes, 'done')

      pipelineFactory(pipes: pipes).callDone().then ->
        pipes.done.should.have.been.calledOnce
        done()
      .catch done

    it 'should not fail when no done callback is present', (done) ->
      pipelineFactory(pipes: {}).callDone().then ->
        done()
      .catch done





