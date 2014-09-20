_ = require 'lodash'
proxyquire = require 'proxyquire'
idkeyvalue = require 'idkeyvalue'
kueStub = {}
kueMock = require './kue'
Pipeline = proxyquire '../../src/Pipeline', 'kue': kueStub

beforeEach ->
  kueStub.createQueue = kueMock.createQueue
  pipelineFactory.kueStub = kueStub

pipelineFactory = (config = {}, force = false) ->
  defaults =
    logger: pipelineFactory.fakeLogger()
    database: pipelineFactory.databaseAdapter()
    dropboxClient: {}

  config = _.merge defaults, config unless force

  new Pipeline config

pipelineFactory.fakeLogger = ->
  log: ->
  warn: ->
  error: ->

pipelineFactory.databaseAdapter = ->
  database = {}
  databaseAdapter = new idkeyvalue.ObjectAdapter database

pipelineFactory.CONSTANTS = Pipeline.CONSTANTS

module.exports = pipelineFactory