# frozen_string_literal: true

module Grape
  class Entity
    module VersionValidations
      def documentation(positional_version = nil, version: nil)
        target_version = version || positional_version
        return @documentation ||= build_documentation if target_version.nil?

        version_key = Version.cast(target_version).to_s
        @versioned_documentation ||= {}
        @versioned_documentation[version_key] ||= build_documentation(target_version)
      end

      def build_documentation(version = nil)
        root_exposures.each_with_object({}) do |exposure, memo|
          next if version && !exposure.version_range.covers?(version)

          memo[exposure.key] = exposure.documentation if exposure.documentation && !exposure.documentation.empty?
        end
      end

      def reset_documentation!
        @documentation = nil
        @versioned_documentation = nil
      end

      def build_exposure_for_attribute(attribute, nesting_stack, options, block)
        exposure_list = nesting_stack.empty? ? root_exposures : nesting_stack.last.nested_exposures
        exposure = Exposure.new(attribute, options)
        remove_override(exposure, nesting_stack) if exposure.override?

        exposure_list << exposure
        return unless exposure.nesting?

        nesting_stack << exposure
        block.call
        nesting_stack.pop
      end

      def validate_version_exposures!
        validate_pairs(root_exposures.map { |exposure| [exposure, exposure.version_range] })
      end

      private

      def validate_pairs(pairs)
        pairs = pairs.reject { |_exposure, range| range.equal?(VersionRange.empty) }
        return if pairs.empty?

        comparable_pairs, = pairs.partition { |exposure, _range| exposure.static_key || exposure.attribute }
        groups = comparable_pairs.group_by do |exposure, _range|
          exposure.static_key || [:attribute, exposure.attribute]
        end
        groups.each_value do |grouped_pairs|
          validate_version_group(grouped_pairs)
        end

        validate_nested_pairs(pairs)
      end

      def validate_version_group(pairs)
        pairs.each_with_index do |(exposure, effective_range), index|
          pairs[(index + 1)..].each do |other_exposure, other_effective_range|
            next unless effective_range.overlap?(other_effective_range)
            next if exposure.nesting? && other_exposure.nesting?

            raise ArgumentError,
                  "overlapping version ranges for #{exposure.static_key.inspect}: " \
                  "#{exposure.version_range} and #{other_exposure.version_range}"
          end
        end
      end

      def validate_nested_pairs(pairs)
        nested_pairs = pairs.select { |exposure, _range| exposure.nesting? }.flat_map do |parent_exposure, parent_range|
          parent_exposure.nested_exposures.map do |nested_exposure|
            [nested_exposure, effective_version_range(nested_exposure, parent_range)]
          end
        end
        nested_pairs = nested_pairs.reject { |_exposure, range| range.equal?(VersionRange.empty) }

        validate_pairs(nested_pairs)
      end

      def effective_version_range(exposure, parent_range)
        parent_range.intersection(exposure.version_range) || VersionRange.empty
      end

      def remove_override(exposure, nesting_stack)
        target_lists =
          if nesting_stack.empty?
            [root_exposures]
          else
            nesting_lists(root_exposures, nesting_stack, 0)
          end

        target_lists.each { |list| list.delete_by_path(exposure.attribute, exposure.static_key) }
      end

      def nesting_lists(lists, nesting_stack, depth)
        active_nesting = nesting_stack[depth]
        matching_nestings = lists.select(&:nesting?).select do |exposure|
          same_exposure_path?(exposure, active_nesting)
        end
        previous_nestings = matching_nestings.reject { |exposure| exposure.equal?(active_nesting) }

        previous_nestings.flat_map do |nesting|
          if depth == nesting_stack.size - 1
            [nesting.nested_exposures]
          else
            nesting_lists(nesting.nested_exposures, nesting_stack, depth + 1)
          end
        end
      end

      def same_exposure_path?(left, right)
        left.attribute == right.attribute ||
          (left.static_key && right.static_key && left.static_key == right.static_key)
      end
    end
  end
end
