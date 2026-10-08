# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Small shared utilities for schema building.
      module Helpers
        private

        def warning(exposure, code, message)
          {
            'attribute' => exposure.attribute&.to_s,
            'code' => code,
            'message' => message
          }
        end

        def stringify_keys(object)
          case object
          when Hash
            object.each_with_object({}) do |(key, value), memo|
              memo[key.to_s] = stringify_keys(value)
            end
          when Array
            object.map { |item| stringify_keys(item) }
          else
            object
          end
        end
      end
    end
  end
end
