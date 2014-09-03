#* CONFIG
#********

argv = require('minimist')(process.argv.slice(2))

USER_ID = argv.userId || false
APP_KEY = argv.appKey
APP_SECRET = argv.appSecret
SERVER_PORT = argv.port || 3000


#* BOOTSTRAP
#***********

ExpressDropboxOAuth = require 'express-dropbox-oauth'
Plumber = require('../src/index').Plumber
Pipeline = require('../src/index').Pipeline
idkeyvalue = require 'idkeyvalue'
express = require 'express'
path = require 'path'
pipes = require './pipes'

credentials =
  key: APP_KEY
  secret: APP_SECRET

# database = {}
database = { global: { 'express-dropbox-auth-code': 'w-Cb5jKN4CcAAAAAAAAnQJhM-f-n1-l32MYa0U8Ywvm2Y4DtqFYqJLqXmjMEe4bH' } }
databaseAdapter = new idkeyvalue.ObjectAdapter database, USER_ID
expressDropboxOAuth = new ExpressDropboxOAuth credentials, databaseAdapter
app = express()


pipeline = false;
startPipeline = (dropboxClient) ->
  return pipeline if pipeline

  pipeline = new Pipeline pipes: pipes, dropboxClient: dropboxClient
  pipeline.start()

  return pipeline

expressDropboxOAuth.checkAuth(->) {}, {}, ->
  startPipeline expressDropboxOAuth.dropboxClient

#* ROUTES
#********

unauthRoute = (err, req, res) ->
  res.send """
    Not authenticated (#{err})
    <a href="/auth">click here to authenticate</a>
  """

app.get '/logout', expressDropboxOAuth.logout(), (req, res) ->
  res.redirect '/'

app.get '/auth', expressDropboxOAuth.doAuth(unauthRoute), (req, res) ->
  console.log database
  res.redirect '/'

app.get '/plumber', expressDropboxOAuth.checkAuth(unauthRoute), (req, res) ->
  plumber = new Plumber({
    dropboxClient: expressDropboxOAuth.dropboxClient,
    database: databaseAdapter,
    pipeline: startPipeline expressDropboxOAuth.dropboxClient
  })
  plumber.start (err) ->
    if err
      console.error err
      return res.send "Unable to start Plumber (#{err})"
    res.send 'Plumber started'

authRoute = (req, res) ->
  expressDropboxOAuth.dropboxClient.getUserInfo (err, user) ->
    res.send """
      Hello #{user.name}, how are you? <a href="/plumber">Start Plumber</a> - <a href='/logout'>logout</a>
    """
app.get '*', expressDropboxOAuth.checkAuth(unauthRoute), authRoute


#* SERVER
#********

server = app.listen SERVER_PORT, ->
  console.log 'Listening on port %d', server.address().port
