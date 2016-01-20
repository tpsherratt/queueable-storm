require 'sidekiq'
# This is a default worker for a default
module Queueable
  class Worker
    include Sidekiq::Worker
    sidekiq_options queue: "queueable-default-queue"

    def perform(clazz, id)
      clazz.constantize.run(id)
    end
  end
end