inPipes =
  '**/*.md': (file, done) ->
    console.log "new MD file."
    done()
  '**': (file, done) ->
    console.log "new Pipeline file."
    done()

outPipes =
  '**': (file, done) ->
    console.log "should remove #{file}"
    done()

done = -> console.log 'DONE'

error = (err) -> console.log 'GOT ERROR', err

module.exports =
  in: inPipes
  out: outPipes
  done: done
  error: error
