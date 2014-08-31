module.exports =
	in: {
		'**/*.md': (file, done) ->
      console.log "new MD file."
      done()
    '**': (file, done) ->
      console.log "new Pipeline file."
      done()
  }