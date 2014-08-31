describe 'Pipeline', ->
  proxyquire = require 'proxyquire'
  _ = require 'lodash'
  taskmanStub = {}
  Pipeline = proxyquire '../src/Pipeline', 'node-taskman': taskmanStub

  fakeLogger = null

  pipelineFactory = (customConfig = {}) ->
    defaults =
      logger: fakeLogger

    config = _.merge defaults, customConfig
    new Pipeline config

  beforeEach ->
    fakeLogger =
      log: sinon.spy()

  it 'should exist', ->
    pipelineFactory().should.exist

  it 'should have a queue property, we can push on', ->
    pipeline = pipelineFactory()
    pipeline.queue.should.exist
    pipeline.queue.push.should.be.an.instanceof Function

  describe 'start', ->
    it 'should start a taskman worker and register the preprocessor', ->
      fakeWorker = process: sinon.spy()
      taskmanStub.createWorker = sinon.stub().returns fakeWorker
      pipeline = pipelineFactory()
      pipeline.start()

      taskmanStub.createWorker.should.have.been.calledOnce
      taskmanStub.createWorker.should.have.been.calledWith Pipeline.CONSTANTS.FILE_PROCESSOR_WORKER_ID
      fakeWorker.process.should.have.been.calledOnce
      fakeWorker.process.should.have.been.calledWith pipeline.preprocessor

  describe 'preprocessor', ->
    it 'should pass changes to process', (done) ->
      pipeline = pipelineFactory()
      sinon.stub(pipeline, 'process').returns true

      someChanges = [{change: 'hello'}, {change: 'world'}]

      pipeline.preprocessor someChanges, ->
        pipeline.process.should.have.been.calledTwice
        pipeline.process.getCall(0).args[0].should.equal someChanges[0].change
        pipeline.process.getCall(1).args[0].should.equal someChanges[1].change
        done()



