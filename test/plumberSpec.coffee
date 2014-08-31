describe 'Plumber', ->
  proxyquire = require 'proxyquire'
  idkeyvalue = require 'idkeyvalue'
  taskmanStub = {}
  Plumber = proxyquire './../src/Plumber', 'node-taskman': taskmanStub
  database = null
  databaseAdapter = null
  fakeDropboxClient = null

  beforeEach ->
    fakeDropboxClient =
      delta: ->
    database = {}
    databaseAdapter = new idkeyvalue.ObjectAdapter database

  it 'should exist', ->
    plumber = new Plumber dropboxClient: fakeDropboxClient
    plumber.should.exist

  describe 'dropbox', ->
    it 'should take a dropbox Client', ->
      plumber = new Plumber dropboxClient: fakeDropboxClient
      plumber.dropboxClient.should.equal fakeDropboxClient

    describe 'get delta', ->
      it 'should take an optional logger', ->
        myLogger =
          log: sinon.spy()

        myLogOutput = 'hello log'

        plumber = new Plumber logger: myLogger
        plumber.log.log myLogOutput

        myLogger.log.should.have.been.calledWith myLogOutput

      it 'should do a dropbox delta call when started', (done) ->
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, 'fail'

        plumber = new Plumber
          dropboxClient: fakeDropboxClient
          database: databaseAdapter

        plumber.start ->
          fakeDropboxClient.delta.should.have.been.called
          done()

      it 'should pass errors from dropbox client', (done) ->
        myError = new Error 'Foo is Bar'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, myError

        plumber = new Plumber
          dropboxClient: fakeDropboxClient
          database: databaseAdapter

        plumber.start (err) ->
          myError.should.equal err
          done()

      it 'should save the cursorTag', (done) ->
        myCursorTag = 'foo'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, cursorTag: myCursorTag
        sinon.spy(databaseAdapter, 'set')

        plumber = new Plumber
          dropboxClient: fakeDropboxClient
          database: databaseAdapter

        plumber.start ->
          databaseAdapter.set.should.have.been.calledWith Plumber.CONSTANTS.CURSOR_TAG_KEY, myCursorTag
          done()

      it 'should call delta with a cursor when present', (done) ->
        myStoredCursorTag = 'xyz'
        databaseAdapter.set Plumber.CONSTANTS.CURSOR_TAG_KEY, myStoredCursorTag, ->
          sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, 'fail'

          plumber = new Plumber
            dropboxClient: fakeDropboxClient
            database: databaseAdapter

          plumber.start ->
            fakeDropboxClient.delta.getCall(0).args[0].cursorTag.should.equal myStoredCursorTag
            done()

      it 'should pass errors from idkeyvalue', (done) ->
        myError = new Error 'Bar is Foo'
        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, cursorTag: 'baz'
        sinon.stub(databaseAdapter, 'set').callsArgWithAsync 2, myError

        plumber = new Plumber
          dropboxClient: fakeDropboxClient
          database: databaseAdapter

        plumber.start (err) ->
          myError.should.equal err
          done()

      it 'should queue delta changes to taskman', (done) ->
        fakeQueue = [];
        sinon.spy fakeQueue, 'push'
        taskmanStub.createQueue = sinon.stub().returns fakeQueue
        myChanges = [{path: 'bar.txt'}, {path: 'ipsum.md'}]

        sinon.stub(fakeDropboxClient, 'delta').callsArgWithAsync 1, null, {cursorTag: 'baz', changes: myChanges}

        plumber = new Plumber
          dropboxClient: fakeDropboxClient
          database: databaseAdapter

        plumber.start ->
          taskmanStub.createQueue.should.have.been.calledWith Plumber.CONSTANTS.FILE_PROCESSOR_WORKER_ID
          fakeQueue.push.should.have.been.calledTwice
          fakeQueue.push.getCall(0).args[0].change.should.equal myChanges[0]
          fakeQueue.push.getCall(1).args[0].change.should.equal myChanges[1]
          done()

      it 'should pull again if told so', (done) ->
        sinon.stub(fakeDropboxClient, 'delta')
          .onCall(0).callsArgWithAsync 1, null, {cursorTag: 'foo', shouldPullAgain: true}
          .onCall(1).callsArgWithAsync 1, null, {cursorTag: 'baz', shouldPullAgain: false}

        plumber = new Plumber
          dropboxClient: fakeDropboxClient
          database: databaseAdapter

        sinon.spy plumber, 'start'

        plumber.start ->
          plumber.start.should.have.been.calledTwice
          done()

