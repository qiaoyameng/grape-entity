# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Reads and applies the declared `documentation:` metadata.
      module DocumentationSupport
        private

        def documentation_hash(exposure)
          doc = exposure.documentation
          doc.is_a?(Hash) ? doc : nil
        end

        def explicit_schema(exposure)
          doc = documentation_hash(exposure)
          return nil unless doc

          doc[:schema] || doc[:json_schema]
        end

        def fragment_from_documentation(doc)
          return stringify_keys(doc[:schema] || doc[:json_schema]) if doc[:schema] || doc[:json_schema]
          return nil unless doc.key?(:type)

          JsonSchema.fragment_for_type(doc[:type])
        end

        def apply_documentation(fragment, exposure)
          doc = documentation_hash(exposure)
          return fragment if doc.nil? || doc[:schema] || doc[:json_schema]

          fragment = fragment.dup
          fragment['description'] = doc[:desc].to_s if doc[:desc]
          values = if doc[:values].is_a?(Array)
                     doc[:values]
                   else
                     doc[:enum].is_a?(Array) ? doc[:enum] : nil
                   end
          fragment['enum'] = values if values
          fragment
        end

        def nullable?(exposure)
          doc = documentation_hash(exposure)
          doc && doc[:nullable] == true
        end

        def add_condition_notes(fragment, exposure)
          return fragment unless exposure.conditional?

          descriptions = exposure.conditions.filter_map { |condition| JsonSchema.describe_condition(condition) }
          return fragment if descriptions.empty?

          fragment[JsonSchema::NOTE_KEY] =
            "field presence is conditional (#{descriptions.join('; ')}); marked optional"
          fragment
        end
      end
    end
  end
end
