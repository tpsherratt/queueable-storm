module Queueable
  module StormManager
    def self.included(klazz)
      klazz.class_eval do
        before_save :set_status
        before_save :set_attempts
      end

      def set_attempts(obj)
        # Shit hack - need to implement before_create callbacks in storm - easier said than done...
        return unless obj.id.nil? && obj.attempts.nil?
        obj.set_attempts 
      end

      def set_status(obj)
        # Shit hack - need to implement before_create callbacks in storm - easier said than done...
        return unless obj.id.nil? && obj.status.nil?
        obj.set_status
      end
    end
  end
end