require 'sucker_punch'
require 'pact_broker/webhooks/service'
require 'pact_broker/logging'

module PactBroker
  module Webhooks
    class Job

      BACKOFF_TIMES = [10, 60, 120, 300, 600, 1200] #10 sec, 1 min, 2 min, 5 min, 10 min, 20 min => 38 minutes

      include SuckerPunch::Job
      include PactBroker::Logging

      def perform data
        @data = data
        @triggered_webhook = data[:triggered_webhook]
        @error_count = data[:error_count] || 0
        begin
          webhook_execution_result = PactBroker::Webhooks::Service.execute_triggered_webhook_now triggered_webhook
          reschedule_job unless webhook_execution_result.success?
        rescue StandardError => e
          handle_error e
        end
      end

      private

      attr_reader :triggered_webhook, :error_count

      def handle_error e
        log_error e
        reschedule_job
      end

      def reschedule_job
        case error_count
        when 0...BACKOFF_TIMES.size
          logger.debug "Re-enqeuing job for webhook #{triggered_webhook.webhook_uuid} to run in #{BACKOFF_TIMES[error_count]} seconds"
          Job.perform_in(BACKOFF_TIMES[error_count], @data.merge(error_count: error_count+1))
        else
          logger.error "Failed to execute webhook #{triggered_webhook.webhook_uuid} after #{BACKOFF_TIMES.size} times."
        end
      end

    end
  end
end
