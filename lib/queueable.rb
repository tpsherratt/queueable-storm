require "queueable/storm_manager"
require "queueable/storm_model"
require "queueable/version"
require "queueable/worker"

module Queueable
  # include the right files in the right places
  def self.included(klazz)
    klazz.include(StormModel)
  end

  # status constants
  DONE = 0
  PROCESSING = 1
  QUEUED = 2
  WAITING = 3
  FILTERED = 4
  REJECTED = 5
  ERRORED = 9
end