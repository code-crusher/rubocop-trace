# frozen_string_literal: true

module RuboCop
  module Cop
    module Lint
      # Checks for unreachable code.
      # The check is based on the presence of flow-of-control
      # statements in non-final position in `begin` (implicit) blocks.
      #
      # The offense is reported on the statement that makes the following code
      # unreachable, rather than on every statement that follows it.
      #
      # @example
      #
      #   # bad
      #   def some_method
      #     return
      #     do_something
      #   end
      #
      #   # bad
      #   def some_method
      #     if cond
      #       return
      #     else
      #       return
      #     end
      #     do_something
      #   end
      #
      #   # good
      #   def some_method
      #     do_something
      #   end
      class UnreachableCode < Base
        MSG = 'Code following an always-true guard statement will never run.'

        def initialize(config = nil, options = nil)
          super
          @redefined = []
          @reported_guards = []
          @instance_eval_count = 0
        end

        def on_new_investigation
          super
          @reported_guards = []
        end

        def on_block(node)
          @instance_eval_count += 1 if instance_eval_block?(node)
        end

        alias on_numblock on_block
        alias on_itblock on_block

        def after_block(node)
          @instance_eval_count -= 1 if instance_eval_block?(node)
        end

        def on_begin(node)
          # A guard that was already reported for an enclosing branch makes the
          # code it contains unreachable too, but reporting it again would only
          # repeat the same warning.
          return if reported_guard_ancestor?(node)

          expressions = *node

          # The first flow-of-control statement that is not the final expression
          # makes everything after it unreachable, so it is the only statement
          # worth reporting.
          expressions[0...-1].each do |expression|
            guard = unconditional_guard(expression)
            next unless guard

            @reported_guards << guard
            add_offense(guard)
            break
          end
        end

        alias on_kwbegin on_begin

        private

        # Checks whether the node is inside a guard that has already been
        # reported, in which case its own unreachable code is not reported
        # again.
        def reported_guard_ancestor?(node)
          @reported_guards.any? { |guard| guard.source_range.contains?(node.source_range) }
        end

        def redefinable_flow_method?(method)
          %i[raise fail throw exit exit! abort].include? method
        end

        # @!method flow_command?(node)
        def_node_matcher :flow_command?, <<~PATTERN
          {
            return next break retry redo
            (send
             {nil? (const {nil? cbase} :Kernel)}
             #redefinable_flow_method?
             ...)
          }
        PATTERN

        # Returns the node that makes the expressions following it unreachable,
        # or `nil` if the given expression can complete normally.
        # rubocop:disable-next Metrics/CyclomaticComplexity
        def unconditional_guard(node)
          return node if flow_command?(node) && report_on_flow_command?(node)

          case node.type
          when :begin, :kwbegin
            guard_in_begin(node)
          when :if
            node if check_if(node)
          when :case, :case_match
            node if check_case(node)
          when :def, :defs
            register_redefinition(node)
            nil
          end
        end

        def guard_in_begin(node)
          expressions = *node
          expressions.each do |expression|
            guard = unconditional_guard(expression)
            return guard if guard
          end
          nil
        end

        def check_if(node)
          if_branch = node.if_branch
          else_branch = node.else_branch
          if_branch && else_branch && unconditional_guard(if_branch) &&
            unconditional_guard(else_branch)
        end

        def check_case(node)
          else_branch = node.else_branch
          return false unless else_branch
          return false unless unconditional_guard(else_branch)

          branches = node.case_type? ? node.when_branches : node.in_pattern_branches

          branches.all? { |branch| branch.body && unconditional_guard(branch.body) }
        end

        def register_redefinition(node)
          @redefined << node.method_name if redefinable_flow_method?(node.method_name)
        end

        def instance_eval_block?(node)
          node.any_block_type? && node.method?(:instance_eval)
        end

        def report_on_flow_command?(node)
          return true unless node.send_type?

          # By the contract of this function, this case means that
          # the method is called on `Kernel` in which case we
          # always want to report a warning.
          return true if node.receiver

          # Inside an `instance_eval` we have no way to tell the
          # type of `self` just by looking at the AST, so we can't
          # tell if the give function that's called has been
          # redefined or not, so to avoid false positives, we silence
          # the warning.
          return false if @instance_eval_count.positive?

          !@redefined.include? node.method_name
        end
      end
    end
  end
end
