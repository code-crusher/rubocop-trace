# frozen_string_literal: true

module RuboCop
  module Cop
    module Style
      # Flags uses of `OpenStruct`, as it is now officially discouraged
      # to be used for performance, version compatibility, and potential security issues.
      #
      # @safety
      #   Note that this cop may flag false positives; for instance, the following legal
      #   use of a hand-rolled `OpenStruct` type would be considered an offense:
      #
      #   [source,ruby]
      #   -----
      #   module MyNamespace
      #     class OpenStruct # not the OpenStruct we're looking for
      #     end
      #
      #     def new_struct
      #       OpenStruct.new # resolves to MyNamespace::OpenStruct
      #     end
      #   end
      #   -----
      #
      #   Autocorrection is unsafe as well. It rewrites `OpenStruct.new(x: 0, y: 1)` as
      #   `Data.define(:x, :y).new(0, 1)`, which is an immutable value object: the
      #   attributes cannot be assigned after construction, and methods such as `#[]=`,
      #   `#each_pair` and `#delete_field` are gone. The class is also created anonymously
      #   at every call, so the result is not `==` to an instance of another `Data.define`
      #   class with the same members. The correction is only made when the target Ruby
      #   version is 3.2 or higher, where `Data` is available, and when every key is a
      #   symbol naming a valid member, so the generated code is valid Ruby.
      #
      # @example
      #
      #   # bad
      #   point = OpenStruct.new(x: 0, y: 1)
      #
      #   # good
      #   Point = Struct.new(:x, :y)
      #   point = Point.new(0, 1)
      #
      #   # also good
      #   point = { x: 0, y: 1 }
      #
      #   # bad
      #   test_double = OpenStruct.new(a: 'b')
      #
      #   # good (assumes test using rspec-mocks)
      #   test_double = double
      #   allow(test_double).to receive(:a).and_return('b')
      #
      class OpenStructUse < Base
        include RangeHelp
        extend AutoCorrector

        MSG = 'Avoid using `OpenStruct`; use `Struct`, `Hash`, a class or test doubles instead.'
        MEMBER_NAME = /\A[a-zA-Z_]\w*[?!]?\z/.freeze

        # @!method uses_open_struct?(node)
        def_node_matcher :uses_open_struct?, <<~PATTERN
          (const {nil? (cbase)} :OpenStruct)
        PATTERN

        # @!method open_struct_new?(node)
        def_node_matcher :open_struct_new?, <<~PATTERN
          (send (const {nil? (cbase)} :OpenStruct) :new ...)
        PATTERN

        def on_const(node)
          return unless uses_open_struct?(node)
          return if custom_class_or_module_definition?(node)

          add_offense(node) do |corrector|
            correct_open_struct(node, corrector)
          end
        end

        private

        def custom_class_or_module_definition?(node)
          parent = node.parent

          parent&.type?(:class, :module) && node.left_siblings.empty?
        end

        def correct_open_struct(node, corrector)
          return unless target_ruby_version >= 3.2

          new_node = node.parent
          hash = correctable_hash(new_node)
          return unless hash

          corrector.replace(node, "#{data_constant(node)}.define(#{member_list(hash)})")
          correct_arguments(new_node, hash, corrector)
        end

        def data_constant(node)
          node.absolute? ? '::Data' : 'Data'
        end

        def member_list(hash)
          hash.pairs.map { |pair| ":#{pair.key.value}" }.join(', ')
        end

        # Replaces each `key: value` pair with its value in place, so that the layout and any
        # comments of the original call are kept. A braced hash is replaced as a whole, and a
        # call without parentheses gets parentheses, since `Data.define(...).new 0, 1` is
        # easily misread.
        def correct_arguments(new_node, hash, corrector)
          if hash.braces?
            corrector.replace(hash, value_list(hash))
          elsif new_node.parenthesized_call?
            hash.pairs.each { |pair| corrector.replace(pair, pair.value.source) }
          else
            corrector.replace(argument_range(new_node, hash), "(#{value_list(hash)})")
          end
        end

        def value_list(hash)
          hash.pairs.map { |pair| pair.value.source }.join(', ')
        end

        def argument_range(new_node, hash)
          range_between(new_node.loc.selector.end_pos, hash.source_range.end_pos)
        end

        # Returns the hash argument when the call can be rewritten as
        # `Data.define(...).new(...)`, or `nil` when it cannot be rewritten without changing
        # more than the documented loss of mutability.
        def correctable_hash(new_node)
          return unless open_struct_new?(new_node) && !new_node.block_literal?

          hash = single_hash_argument(new_node)
          hash if hash && convertible_hash?(new_node, hash)
        end

        def single_hash_argument(new_node)
          return unless new_node.arguments.one?

          hash = new_node.first_argument
          hash if hash.hash_type? && hash.children.all?(&:pair_type?)
        end

        def convertible_hash?(new_node, hash)
          return false if hash.pairs.empty? || nested_correctable_open_struct?(hash)
          return false unless convertible_members?(hash.pairs)

          !drops_comment?(hash, replaced_ranges(new_node, hash))
        end

        def convertible_members?(pairs)
          names = pairs.map { |pair| member_name(pair) }

          names.none?(&:nil?) && names.uniq.size == names.size
        end

        # The ranges the correction replaces. Everything outside them keeps its source, so
        # a comment is only lost when it lies inside one of them and outside every value.
        def replaced_ranges(new_node, hash)
          if hash.braces?
            [hash.source_range]
          elsif new_node.parenthesized_call?
            hash.pairs.map(&:source_range)
          else
            [argument_range(new_node, hash)]
          end
        end

        def drops_comment?(hash, replaced)
          kept = hash.pairs.map { |pair| pair.value.source_range }

          processed_source.comments.any? do |comment|
            lost?(comment.source_range, replaced, kept)
          end
        end

        def lost?(range, replaced, kept)
          replaced.any? { |r| r.contains?(range) } && kept.none? { |r| r.contains?(range) }
        end

        # Correcting the outer call would overlap the correction of a nested one, which the
        # corrector cannot apply in the same pass. Leave the outer call for the next pass;
        # the nested call is rewritten first, so the outer one is corrected afterwards.
        def nested_correctable_open_struct?(hash)
          hash.each_descendant(:const).any? do |const|
            uses_open_struct?(const) && correctable_hash(const.parent)
          end
        end

        def member_name(pair)
          key = pair.key
          return unless key.sym_type?

          name = key.value.to_s
          name if name.match?(MEMBER_NAME)
        end
      end
    end
  end
end
