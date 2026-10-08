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

          def select_by(attribute)
            @exposures.select { |e| e.attribute == attribute }
          end

          def <<(exposure)
            reset_memoization!
            @exposures << exposure
          end

          def delete_by(*attributes)
            reset_memoization!
            @exposures.reject! { |e| attributes.include? e.attribute }
            @exposures
          end

          def delete_by_path(attribute, key)
            reset_memoization!
            @exposures.reject! { |exposure| exposure.attribute == attribute || (key && exposure.static_key == key) }
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
          def deep_complex_nesting?(entity, options = nil)
            if options.nil?
              @deep_complex_nesting ||= grouping_is_complex?(select(&:nesting?), entity)
            else
              all_nesting = select(&:nesting?).select { |exposure| exposure.valid_for_version?(options) }
              grouping_is_complex?(all_nesting, entity)
            end
          end

          private

          def grouping_is_complex?(exposures, entity)
            exposures
              .group_by { |exposure| exposure.key(entity) }
              .any? { |_key, grouped_exposures| grouped_exposures.length > 1 }
          end

          def reset_memoization!
            @deep_complex_nesting = nil
          end
        end
      end
    end
  end
end
