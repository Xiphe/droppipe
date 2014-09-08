describe 'Plumber', ->
  _ = require 'lodash'
  idkeyvalue = require 'idkeyvalue'
  Plumber = require './../src/Plumber'
  database = null
  databaseAdapter = null
  fakeDropboxClient = null
  fakeLogger = null
  changeQueue = null

  plumberFactory = (customConfig = {}) ->
    defaults =
      dropboxClient: fakeDropboxClient
      database: databaseAdapter
      logger: fakeLogger
      pipeline: addJob: ->

    config = _.merge defaults, customConfig
    new Plumber config

  beforeEach ->
    changeQueue = []
    fakeDropboxClient =
      delta: ->
      credentials: ->
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

      it 'should queue delta changes to kue', (done) ->
        plumber = plumberFactory()
        pipeline = plumber.pipeline

        sinon.spy pipeline, 'addJob'
        myChanges = [{path: 'bar.txt'}, {path: 'ipsum.md', wasRemoved: true}]
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, {cursorTag: 'baz', changes: myChanges}


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


