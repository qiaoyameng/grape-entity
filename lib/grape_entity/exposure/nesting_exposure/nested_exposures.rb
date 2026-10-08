# frozen_string_literal: true

module Grape
  class Entity
    module Exposure
      class NestingExposure
        class NestedExposures
          include Enumerable

          def initialize(exposures)
            @exposures = exposures
            @deep_complex_nesting = nil
          end

          def find_by(attribute)
            @exposures.find { |e| e.attribute == attribute }
          end

          # Documentation of the exposures available for the given version.
          def documentation(version)
            @exposures.each_with_object({}) do |exposure, memo|
              next unless exposure.documentation && !exposure.documentation.empty?
              next unless exposure.version_in_range?(version)

              memo[exposure.key] = exposure.documentation
            end
          end

          def select_by(attribute)
            @exposures.select { |e| e.attribute == attribute }
          end

          def <<(exposure)
            reset_memoization!
            validate_version_range_overlap!(exposure)
            @exposures << exposure
          end

          def delete_by(*attributes)
            reset_memoization!
            @exposures.reject! { |e| attributes.include? e.attribute }
            @exposures
          end

          def clear
            reset_memoization!
            @exposures.clear
          end

          # rubocop:disable Style/DocumentDynamicEvalDefinition
          %i[
            each
            to_ary to_a
            all?
            select
            each_with_object
            \[\]
            ==
            size
            count
            length
            empty?
          ].each do |name|
            class_eval <<-RUBY, __FILE__, __LINE__ + 1
              def #{name}(*args, &block)
                @exposures.#{name}(*args, &block)
              end
            RUBY
          end
          # rubocop:enable Style/DocumentDynamicEvalDefinition

          # Determine if we have any nesting exposures with the same name.
          def deep_complex_nesting?(entity)
            if @deep_complex_nesting.nil?
              all_nesting = select(&:nesting?)
              @deep_complex_nesting =
                all_nesting
                .group_by { |exposure| exposure.key(entity) }
                .any? { |_key, exposures| exposures.length > 1 }
            else
              @deep_complex_nesting
            end
          end

          private

          # Two exposures writing to the same output path may coexist only
          # when their version ranges do not overlap. The check runs at build
          # time so invalid declarations fail fast. It is consistent with
          # :override, which removes previous declarations of the same
          # attribute before the new exposure is appended.
          def validate_version_range_overlap!(new_exposure)
            new_range = new_exposure.version_range
            new_key = new_exposure.static_key
            return if new_range.nil? || new_key.nil?

            @exposures.each do |existing|
              existing_range = existing.version_range
              next if existing_range.nil? || existing.static_key != new_key
              next unless new_range.overlaps?(existing_range)

              raise ArgumentError,
                    "#{new_key.inspect} is already exposed for an overlapping version range; " \
                    'declare non-overlapping :since/:until ranges or use :override to replace it'
            end
          end

          def reset_memoization!
            @deep_complex_nesting = nil
          end
        end
      end
    end
  end
end
