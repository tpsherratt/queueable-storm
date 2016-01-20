module Queueable
  module StormModel
    module ClassMethods
      def run(id)
        resource = @manager.find(id)

        return unless resource.processable?
        resource.status = Queueable::PROCESSING
        @manager.save! resource

        begin
          # allow the resouce to define a filter? method, to stop it being processed
          if resource.respond_to?(:filter?) && resource.filter?
            resource.status = Queueable::FILTERED
            @manager.save! resource
            return  
          end
          # allow the resource to define ready? method, to stop it being processed right now...
          if resource.respond_to?(:ready?) && !resource.ready?

            resource.status = Queueable::QUEUED
            resource.attempts += 1
            @manager.save! resource
            # process later
            resource.process
            return
          end

          processed = false
          # if something goes wrong this call should error, and be allowed to propogate up!
          processed = resource.send(@run_method)

        rescue Exception => e
          resource.status = Queueable::ERRORED
          # save the error, if we can
          if resource.respond_to?(:ers)
            error = "Error processing #{resource.class.name} #{resource.id}: #{e.message}"
            resource.ers ||= []
            resource.ers << error
            resource.ers << e.backtrace.join("\n")
          end
          @manager.save! resource
          raise e
        ensure
          resource.processed_at = Time.now
          @manager.save resource
        end

        resource.status = Queueable::DONE if processed
        resource.status = Queueable::REJECTED unless processed
        @manager.save resource
      end

      def queueable(options={})
        # store this shit in class instance vars,
        # The manager for this class
        raise "Manager must be set" if options[:manager].nil?
        @manager = options[:manager].new

        # There's probably a better place for this, not sure where though. TS
        options[:manager].include(Queueable::StormManager)

        # TODO: check the worker is valid
        @worker = options[:worker] if options.has_key? :worker
        # TODO: check the run_method is valid
        @run_method = options[:run_method] if options.has_key? :run_method
      end

      # class method to access the worker
      def worker
        @worker
      end

      # class method to access the run method
      def run_method
        @run_method
      end
    end

    def self.included(klazz)
      klazz.class_eval do
        attributes :id, :status, :attempts, :ers, :processed_at

        # store the config in class instance vars
        @worker = Worker
        @run_method = :run
      end

      klazz.extend(ClassMethods)
    end

    # for callback
    def set_status
      self.status = Queueable::QUEUED
    end

    # for callback
    def set_attempts
      self.attempts = 0
    end
 
################################################################################
## Checkers   
# check for done status
    def done? 
      self.status == Queueable::DONE
    end

# check if it will not be processed in the future
    def finished_processing?
      self.status == Queueable::FILTERED ||
        self.status == Queueable::REJECTED ||
        self.status == Queueable::DONE
    end

    def processable?
      self.status == Queueable::QUEUED || 
        self.status == Queueable::ERRORED ||
        self.status == Queueable::FILTERED
    end

    def is_queueable?
      true
    end

    # Process Methods
    # These basically just call self.run with a little sidekiq magic sprinkled in
    def process
      process_now if self.attempts == 0 # do it as soon as possible
      process_delayed((2**self.attempts).seconds) if self.attempts > 0 # delay...
    end

    # make a process fire at a specific time
    def process_at(time)
      return process_now if time <= DateTime.now.utc
      process_delayed(time - DateTime.now.utc)
    end

    # make a process fire after a delay
    def process_delayed(delay)
      return process_now if delay <= 0
      self.class.worker.perform_in(delay, self.class.name, self.id)
    end

    private 
    # this one shouldn't be called directly - should go through process, so 
    # attempts get processed properly
    def process_now
      self.class.worker.perform_async(self.class.name, self.id)
    end

  end
end
