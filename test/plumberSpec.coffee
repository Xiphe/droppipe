describe 'Plumber', ->
  _ = require 'lodash'
  idkeyvalue = require 'idkeyvalue'
  Plumber = require '../src/Plumber'
  kueMock = require './mocks/kue'
  pipelineFactory = require './mocks/pipeline'
  Q = require 'q'

  database = null
  databaseAdapter = null
  fakeDropboxClient = null
  fakeLogger = null
  changeQueue = null
  kueStub = null

  plumberFactory = (customConfig = {}) ->
    defaults =
      dropboxClient: fakeDropboxClient
      database: databaseAdapter
      logger: fakeLogger
      pipeline: addJob: ->

    config = _.merge defaults, customConfig
    new Plumber config

  beforeEach ->
    kueStub = pipelineFactory.kueStub
    changeQueue = []
    fakeDropboxClient =
      delta: ->
      credentials: ->
      metadata: ->
    database = {}
    databaseAdapter = new idkeyvalue.ObjectAdapter database
    fakeLogger =
      log: sinon.spy()
      warn: sinon.spy()

  it 'should exist', ->
    plumber = plumberFactory()
    plumber.should.exist

  describe 'dropbox', ->
    it 'should take a dropbox Client', ->
      plumber = new Plumber dropboxClient: fakeDropboxClient
      plumber.dropboxClient.should.equal fakeDropboxClient

    describe 'get delta', ->
      it 'should use a given logger', ->
        myLogOutput = 'hello log'

        plumber = plumberFactory()
        plumber.logger.log myLogOutput

        fakeLogger.log.should.have.been.calledWith myLogOutput

      it 'should do a dropbox delta call when started', (done) ->
        myError = new Error 'fail'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, myError

        plumberFactory().start (err) ->
          return done err if err && err != myError
          fakeDropboxClient.delta.should.have.been.called
          done()

      it 'should pass errors from dropbox client', (done) ->
        myError = new Error 'Foo is Bar'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, myError

        plumberFactory().start (err) ->
          myError.should.equal err
          done()

      it 'should save the cursorTag', (done) ->
        myCursorTag = 'foo'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, cursorTag: myCursorTag
        sinon.spy(databaseAdapter, 'set')

        plumberFactory().start (err) ->
          return done err if err
          databaseAdapter.set.should.have.been.calledWith Plumber.CONSTANTS.CURSOR_TAG_KEY, myCursorTag
          done()

      it 'should call delta with a cursor when present', (done) ->
        myError = new Error 'fail'
        myStoredCursorTag = 'xyz'
        databaseAdapter.set Plumber.CONSTANTS.CURSOR_TAG_KEY, myStoredCursorTag, ->
          sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, myError

          plumberFactory().start (err) ->
            return done err if err && err != myError
            fakeDropboxClient.delta.getCall(0).args[0].cursorTag.should.equal myStoredCursorTag
            done()

      it 'should pass errors from idkeyvalue', (done) ->
        myError = new Error 'Bar is Foo'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, cursorTag: 'baz'
        sinon.stub(databaseAdapter, 'set').callsArgWithAsync 2, myError

        plumberFactory().start (err) ->
          myError.should.equal err
          done()

      it 'should add jobs to pipeline', (done) ->
        plumber = plumberFactory()
        pipeline = plumber.pipeline

        sinon.stub(pipeline, 'addJob').returns Q.all []
        myChanges = [{path: 'bar.txt', stat: {path: 'Bar.txt'}}, {path: 'ipsum.md', wasRemoved: true}]
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, {cursorTag: 'baz', changes: myChanges}
        sinon.stub(fakeDropboxClient, 'metadata').callsArgWithAsync 1, null, [{path: 'Ipsum.md'}]


        plumber.start (err) ->
          return done err if err
          pipeline.addJob.should.have.been.calledTwice
          pipeline.addJob.getCall(0).args[0].change.should.equal myChanges[0]
          pipeline.addJob.getCall(1).args[0].change.should.equal myChanges[1]
          done()


      it 'should pull again if told so', (done) ->
        sinon.stub(fakeDropboxClient, 'delta')
          .onCall(0).callsArgWithAsync 1, null, {cursorTag: 'foo', shouldPullAgain: true}
          .onCall(1).callsArgWithAsync 1, null, {cursorTag: 'baz', shouldPullAgain: false}

        plumber = plumberFactory()

        sinon.spy plumber, 'start'

        plumber.start (err) ->
          return done err if err
          plumber.start.should.have.been.calledTwice
          done()

  describe 'callDone', ->
    it 'should callDone when all jobs are done', (done) ->
      pipes = done: (done) -> done()
      pipeline = pipelineFactory(pipes: pipes)
      plumber = plumberFactory(pipeline: pipeline)
      sinon.spy(pipeline, 'callDone')

      myChanges = [{path: 'bar.txt', stat: {path: 'Bar.txt'}}, {path: 'ipsum.md', wasRemoved: true}]
      sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, {cursorTag: 'baz', changes: myChanges}
      sinon.stub(fakeDropboxClient, 'metadata').callsArgWithAsync 1, null, [{path: 'Ipsum.md'}]

      plumber.start().then ->
        kueMock.finishAllJobs ->
          pipeline.callDone.should.have.been.calledOnce
          done()
      .catch done

    it 'should not notify un-existent done pipes', (done) ->
      pipes = {}

      pipeline = pipelineFactory pipes: pipes
      sinon.stub(pipeline, '_process').returns Q.when true

      pipeline.addJob change: path: 'foo.md', stat: path: 'foo.md'
        .then ->
          kueMock.finishAllJobs done
        .catch done

    it 'should not notify the done pipes when not finished', (done) ->
      pipes =
        done: sinon.spy()

      pipeline = pipelineFactory pipes: pipes
      sinon.stub(pipeline, '_process').returns Q.when true

      pipeline.addJob change: path: 'hello.md', stat: path: 'hello.md'
        .then ->
          pipeline.addJob change: path: 'world.md', stat: path: 'world.md'
            .then ->
              kueMock.finishJob 0, ->
                pipes.done.should.not.have.been.called
                done()

        .catch done
