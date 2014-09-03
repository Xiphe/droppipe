describe 'Pipeline', ->
  proxyquire = require 'proxyquire'
  _ = require 'lodash'
  Q = require 'q'
  kueStub = {}
  Pipeline = proxyquire '../src/Pipeline', 'kue': kueStub

  fakeLogger = null
  fakeJobs = null

  pipelineFactory = (customConfig = {}) ->
    defaults =
      logger: fakeLogger
      dropboxClient: {}

    config = _.merge defaults, customConfig
    new Pipeline config

  beforeEach ->
    fakeLogger =
      log: sinon.spy()
      warn: sinon.spy()

    fakeJobs =
      create: -> fakeJobs
      attempts: -> fakeJobs
      process: -> fakeJobs
      save: (done) -> done(); return fakeJobs

    kueStub.createQueue = -> fakeJobs

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
      fakeJobs.process.should.have.been.calledWith Pipeline.CONSTANTS.FILE_PROCESSOR_JOB_ID, pipeline.preprocessor

  describe 'addJob', ->
    it 'should add jobs to a queue', ->
      'implemented'.should.equal true

  describe 'preprocessor', ->
    it 'should pass changes to process', (done) ->
      pipeline = pipelineFactory()
      sinon.stub(pipeline, 'process').returns Q.when true

      fakeJob = data: change: 'hello'

      pipeline.preprocessor fakeJob, (err) ->
        return done(err) if err
        pipeline.process.should.have.been.calledOnce
        pipeline.process.getCall(0).args[0].should.equal fakeJob.data.change
        done()

    it 'should notify the done pipes when finished', ->
       'implemented'.should.equal true


  describe 'process', ->
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
      sinon.stub(pipeline, 'toGulpFileStream').returns true

      return pipeline.process change

    it 'should put new changes the the in pipes', (done) ->
      process(path: '/foo.bar').then ->
        inPipeStub.should.have.been.calledOnce
        done()
      .catch done

    it 'should put removed changes to the out pipe', (done) ->
      relativeFile = 'boo.far'
      process(path: "/#{relativeFile}", wasRemoved: true).then ->
        outPipeStub.should.have.been.calledOnce
        outPipeStub.should.have.been.calledWith relativeFile
        done()
      .catch done

    it 'should not process unmatched files', (done) ->
      coffeeSpy = sinon.spy()
      pipes =
        in: '*.coffee': coffeeSpy

      process({path: '/asdf.js'}, pipes).then ->
        coffeeSpy.should.not.have.been.called
        done()
      .catch done

    it 'should transform changes to gulp files', (done) ->
      myChange = path: '/foo.bar'
      process(myChange).then ->
        pipeline.toGulpFileStream.should.have.been.calledOnce
        pipeline.toGulpFileStream.should.have.been.calledWith myChange
        done()
      .catch done

    it 'should not transform out-changes to gulp files', (done) ->
      myChange = path: '/foo.bar'
      process(path: '/boo.far', wasRemoved: true).then ->
        pipeline.toGulpFileStream.should.not.have.been.calledOnce
        done()
      .catch done


  describe 'toGulpFileStream', ->
    dropboxClient = null
    readFileStub = null

    beforeEach ->
      myContent = new Buffer 'Lorem Ipsum', 'utf-8'
      readFileStub = sinon.stub().callsArgWithAsync 2, null, [myContent, path: '/foo.bar']

      dropboxClient =
        readFile: readFileStub

    it 'should request the files content from dropbox', (done) ->
      myChange = path: '/foo.bar'

      pipelineFactory(dropboxClient: dropboxClient).toGulpFileStream(path: '/foo.bar').then ->
        readFileStub.should.have.been.called
        done()
      .catch done

    it 'should convert the dropbox response to a gulp file stream', (done) ->
      inPipeStub = sinon.stub().callsArgWithAsync 1, null
      pipes =
        in: '**': inPipeStub

      pipelineFactory(dropboxClient: dropboxClient, pipes: pipes).process(path: '/foo.bar').then ->
        inPipeStub.should.have.been.called
        inPipeStub.getCall(0).args[0].pipe.should.be.an.instanceof Function
        done()
      .catch done

  describe 'Error handling', ->
    it 'should not get try to read folders', ->
      'implemented'.should.equal true

    it 'should retry operations on fail', ->
      'implemented'.should.equal true
