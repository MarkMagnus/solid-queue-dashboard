module SolidQueueDashboard
  module Decorators
    class JobsDecorator < SimpleDelegator
      def with_status(status)
        case status.to_sym
        when Job::RUNNING
          running
        when Job::SUCCESS
          success
        when Job::FAILED
          failed
        when Job::SCHEDULED
          scheduled
        when Job::PENDING
          pending
        when Job::RETRIED
          retried
        else
          raise "Invalid status: #{status}"
        end
      end

      def running
        where.associated(:claimed_execution)
      end

      def success
        where.not(finished_at: nil)
          .where.not(id: failed)
          .where.not(id: retried)
      end

      def scheduled
        where(finished_at: nil, scheduled_at: Time.current..)
      end

      def pending
        where(finished_at: nil, scheduled_at: ..Time.current)
          .where.not(id: failed)
          .where.not(id: running)
      end

      def retried_jobs
        sql = """
            select
              t.id,
              t.queue_name,
              t.class_name,
              t.arguments,
              t.priority,
              t.active_job_id,
              t.scheduled_at,
              t.finished_at,
              t.concurrency_key,
              t.created_at,
              t.updated_at
            from (
                select row_number() over (partition by active_job_id order by id) as row, *
                from solid_queue_jobs
                where finished_at is not null and finished_at <= ?
            ) as t where t.row > 1
        """
        SolidQueue::Job.find_by_sql([sql, Time.current])
      end

      def retried_job_ids
        retried_jobs.map(&:id)
      end

      def retried
        where(id: retried_job_ids)
      end

      def failure_rate
        success_count = success.count
        retried_count = retried.count
        failed_count = failed.count

        total = success_count + retried_count + failed_count
        return 0 if total.zero?

        (failed_count + retried_count).to_f / total * 100
      end

      def each
        super do |job|
          yield JobDecorator.new(job)
        end
      end

      def to_a
        super.map { |job| JobDecorator.new(job) }
      end
    end
  end
end
