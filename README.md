Droppipe
========

[![Build Status](https://travis-ci.org/Xiphe/droppipe.svg)](https://travis-ci.org/Xiphe/droppipe)
[![Coverage Status](https://coveralls.io/repos/Xiphe/droppipe/badge.png)](https://coveralls.io/r/Xiphe/droppipe)
[![Dependency Status](https://david-dm.org/Xiphe/droppipe.svg)](https://david-dm.org/Xiphe/droppipe)

__Dynamic, Static Websites!__ _(Yes, that is a thing)_


What do I need that for?
------------------------

 1. On your local machine, you just add a file to your Dropbox.
 2. Dropbox syncs the file to their servers
 3. By using [Dropbox Webhooks](https://www.dropbox.com/developers/webhooks/tutorial),
    your server gets notified about the change
 4. Your server runs droppipe which is polling the changes from dropbox servers
 5. Changes are processed by the [pipes](#pipes)
 6. The pipes automatically build/update a static website for you


What are the benefits?
----------------------

 - You accidentally have a backup of your website in your dropbox ;)
 - All benefits of a static website (fast, save, reliable)
 - No need for local tooling
 - Muliple authors by using dropbox sharing tools
 - There are a bunch of apps for editing and authoring dropbox files


And Internally?
---------------

 - We take an authenticated [dropbox-js client](https://github.com/dropbox/dropbox-js)
 - And make a [delta call to dropbox](https://www.dropbox.com/developers/core/docs#delta)
 - Queueing up new delta changes using [kue](https://github.com/learnboost/kue) and [redis](http://redis.io/)
 - Then fetching file contents from dropbox and creating a [gulp file](https://github.com/gulpjs/gulp-util#new-fileobj)
   for each change
 - These gulp files are passed as [streams](http://nodejs.org/api/stream.html) into
   your [pipeline](#pipeline) using [minimatch](https://github.com/isaacs/minimatch)
 - The pipeline can not build your site with [gulp](https://github.com/gulpjs/gulp), [brunch](https://github.com/brunch/brunch),
   [metalsmith](https://github.com/segmentio/metalsmith) or any hipster thing you like.


Install
-------

    npm install droppipe


Setup
-----

You need a running [redis](http://redis.io/) server,
an authenticated [dropbox-js client](https://github.com/dropbox/dropbox-js)
and an [idkeyvalue](https://github.com/Xiphe/idkeyvalue) interfaced database.

With the start of your app, create and start a new Pipeline and a Plumber

```js
// setup of database and dropbox here...

var droppipe = require('droppipe');
var Pipeline = droppipe.Pipeline;
var Plumber = droppipe.Plumber;

var pipeline = new Pipeline({
  pipes: require('./pipefile.js'),
  dropboxClient: dropbox,
  database: database
});

var plumber = new Plumber({
  dropboxClient: dropbox,
  database: database,
  pipeline: pipeline
});

pipeline.start();
```

Now, whenever you like, trigger `plumber.start()`


Config
------

### Pipeline

```js
{
  pipes: null, // required, pipeobject (see Example pipefile.js)
  database: null, // required, some database interfaced by idkeyvalue
  dropboxClient: null, // required, must be authenticated see dropbox-js
  logger: console, // optional
  jobFailureAttempts: 5, // optional, amount of retries per job
  kueConfig: {}, // optional, config for kue
                 // (See: https://github.com/learnboost/kue)
  jobTimeout: 60 // optional, seconds until a pipes processing
                 // function times out
}
```

### Plumber
```js
{
  pipeline: null, // required, instance of droppipe.Pipeline
  database: null, // required, some database interfaced by idkeyvalue
  dropboxClient: null, // required, must be authenticated see dropbox-js
  logger: console // optional
}
```


Dropbox webhooks
----------------

Here are some [express](http://expressjs.com/) routes if you like to
trigger droppipe with dropbox webhooks.

```js
// setup pipeline and plumber here...
// get dropbox user (dropbox.getUserInfo) here...
// setup express app here...
app.use(bodyParser.json());

var webhookEndpoint = '/dropbox-webhook';

// Required for the #dropbox-webhook-setup-challenge
app.get(webhookEndpoint, function(req, res) {
  if (req.query.challenge && req.query.challenge.length) {
    res.send(req.query.challenge);
  } else {
    res.send(418);
  }
});

// The actual webhook.
app.post(webhookEndpoint, function(req, res) {
  // Make sure we have a valid request with a
  // notification for our user.uid
  if (req.body && req.body.delta &&
    typeof req.body.delta.users === 'array' &&
    req.body.delta.users.indexOf(parseInt(user.uid)) >= 0
  ) {
    plumber.start(function(err) {
      if (err) {
        res.send(500);
        console.error(err);
      } else {
        res.send(202);
      }
    }
    });
  } else {
    res.send(401);
  }
});
````


Pipes
-----

A pipe maps a [glob](https://github.com/isaacs/minimatch) to a processor function, like this:
```js
{
  '**/*.+(jpg|jpeg|png)': function(file, done) {
    // proccess some images here.
    done();
  }
}
```

Pipes are defined in two categories: __in__ and __out__.

There must always be a complementing out pipe for every in pipe
ensuring that the right files are deleted when the source is removed
from dropbox.

### In

__in__-Pipes are called whenever a file is added or updated.

The processor function is called with a [gulp file](https://github.com/gulpjs/gulp-util#new-fileobj)
[stream](http://nodejs.org/api/stream.html) and a done callback.

```js
{
  '**/*.pdf': function(file, done) {
    file
      .pipe(gulp.dest('downloads/pdf'))
      .on('end', done);
  }
}
```

### Out

__out__-Pipes will be used when we remove a file from dropbox.

The processor function is called with the path of the removed item and a done callback.

```js
{
  '**/*.pdf': function(filePath, done) {
    del(path.join('downloads/pdf', filePath), done);
  }
}
```


Example pipefile.js
-------------------

These pipes simply sync all files from dropbox to a webserver, while converting markdown to html files.

```js
var TARGET_DIR = '/var/www/droppipe';
var gulp = require('gulp');
var gutil = require('gulp-util');
var markdown = require('gulp-markdown');
var del = require('del');
var path = require('path');

function dlt(file, callback) {
  del(file, {cwd: TARGET_DIR}, callback);
}

module.exports = {
  in: {
    '**/*.md': function(file, done) {
      file
        .pipe(markdown())
        .pipe(gulp.dest(TARGET_DIR))
        .on('end', done);
    },
    '**': function(file, done) {
      file
        .pipe(gulp.dest(TARGET_DIR))
        .on('end', done);
    }
  },
  out: {
    '**/*.md': function(filePath, done) {
      dlt(gutil.replaceExtension(filePath, '.html'), done);
    },
    '**': dlt
  },
  done: function() {
    console.log('Updated Successful');
  },
  error: function(err) {
    console.error('Something went wrong', err);
  }
};
```

License
-------

> The MIT License
> 
> Copyright (c) 2014 Hannes Diercks
> 
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
> 
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
> 
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.
