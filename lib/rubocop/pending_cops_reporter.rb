# frozen_string_literal: true

module RuboCop
  # Reports information about pending cops that are not explicitly configured.
  #
  # This class is responsible for displaying warnings when new cops have been added to RuboCop
  # but have not yet been enabled or disabled in the user's configuration.
  # It provides a centralized way to determine whether such warnings should be shown,
  # based on global flags or configuration settings.
  class PendingCopsReporter
    class << self
      PENDING_BANNER = <<~BANNER
        The following cops were added to RuboCop, but are not configured. Please set Enabled to either `true` or `false` in your `.rubocop.yml` file.

        To opt-in to new cops by default, add this to your config:
          AllCops:
            NewCops: enable
      BANNER

      attr_accessor :disable_pending_cops, :enable_pending_cops

      def warn_if_needed(config)
        return if disable_pending_cops || enable_pending_cops

        pending_cops = pending_cops_only_qualified(config.pending_cops)
        warn_on_pending_cops(pending_cops) unless pending_cops.empty?
      end

      private

      def pending_cops_only_qualified(pending_cops)
        pending_cops.select { |cop| Cop::Registry.qualified_cop?(cop.name) }
      end

      def warn_on_pending_cops(pending_cops)
        warn Rainbow(PENDING_BANNER).yellow

        summary = "#{pending_cops.size} pending cop#{'s' if pending_cops.size > 1}: " \
                  "#{pending_cops.map(&:name).join(', ')}"
        warn Rainbow(summary).yellow

        warn Rainbow('For more information: https://docs.rubocop.org/rubocop/versioning.html').yellow
      end
    end
  end
end
