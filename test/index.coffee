require 'mocha'
require('chai').use(require 'sinon-chai').should()
sinon = require 'sinon'
sandbox = null

beforeEach ->
    sandbox = global.sinon = sinon.sandbox.create()

afterEach ->
    sandbox.restore()

describe 'setup', ->
  it 'should test', ->
    false.should.not.be.ok
    5.should.equal 5
    test = {a: 'b'}
    {a: 'b'}.should.not.equal test
    {a: 'b'}.should.deep.equal test

  it 'should have spies', ->
    spy = sinon.spy()
    spy 5
    spy.should.have.been.calledWith 5

require './plumberSpec'
