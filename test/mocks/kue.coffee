
fakeKue =
  jobs: []
  finishJob: (i, done) ->
    fakeKue.jobs[i].events.complete()
    setTimeout done, 0

  finishAllJobs: (done) ->
    fakeKue.jobs.forEach (job) ->
      job.events.complete()
    setTimeout done, 0

  createQueue: ->
    fakeJobCount = 0

    fakeJobFactory = ->
      job =
        events: {}
        id: fakeJobCount++
        attempts: -> job
        save: (done) -> done?(); return job
        on: (key, callback) -> this.events[key] = callback; return job

      fakeKue.jobs.push job
      return job

    return {
      create: fakeJobFactory
      process: ->
    }

beforeEach ->
  fakeKue.jobs = []

module.exports = fakeKue
