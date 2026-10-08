# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Resolves a single exposure to its JSON Schema fragment.
      module ExposureFragment
        private

        def property_fragment(exposure, only, except)
          fragment =
            if (explicit = explicit_schema(exposure))
              stringify_keys(explicit)
            else
              inferred_fragment(exposure, only, except)
            end

          fragment = apply_documentation(fragment, exposure)
          fragment = JsonSchema.nullable(fragment) if nullable?(exposure)
          add_condition_notes(fragment, exposure)
        end

        def inferred_fragment(exposure, only, except)
          case exposure
          when Exposure::RepresentExposure then represent_fragment(exposure, only, except)
          when Exposure::NestingExposure then object_fragment(exposure.nested_exposures, only, except)
          when Exposure::FormatterBlockExposure, Exposure::FormatterExposure
            formatter_fragment(exposure)
          when Exposure::BlockExposure
            generic_fragment(exposure, 'block-value')
          else
            delegator_fragment(exposure)
          end
        end

        def represent_fragment(exposure, only, except)
          doc = documentation_hash(exposure)
          explicit = doc && (doc[:schema] || doc[:json_schema])

          if exposure.using_class.respond_to?(:root_exposures)
            represent_entity(exposure, doc, explicit, only, except)
          else
            (explicit && stringify_keys(explicit)) ||
              generic_fragment(exposure, 'using-not-entity', using_not_entity_note(exposure))
          end
        end

        def represent_entity(exposure, doc, explicit, only, except)
          return stringify_keys(explicit) if explicit

          declared = doc && doc_type_fragment(doc)
          if declared && !generic_object_or_array?(declared)
            # A specific primitive type still wins, but a vague
            # "Object"/"Array" must not hide the nested entity.
            return declared
          end

          schema = entity_ref(exposure.using_class, only, except)
          if collection?(exposure) || present_collection_exposure?(exposure)
            # Grape::Entity emits nil for a missing represented collection.
            { 'type' => %w[array null],
              'items' => { 'oneOf' => [schema, { 'type' => 'null' }] } }
          else
            { 'oneOf' => [schema, { 'type' => 'null' }] }
          end
        end

        def doc_type_fragment(doc)
          return nil unless doc.key?(:type)

          JsonSchema.fragment_for_type(doc[:type])
        end

        def generic_object_or_array?(fragment)
          %w[object array].include?(fragment['type']) &&
            !fragment.key?('properties') && !fragment.key?('items')
        end

        # With `present_collection true`, the collection accessor receives
        # the whole input array during represent.
        def present_collection_exposure?(exposure)
          @present_collection_enabled ||= present_collection?
          @present_collection_enabled && exposure.attribute == @entity.collection_name
        end

        def formatter_fragment(exposure)
          declared = documentation_type_fragment(exposure)
          return declared if declared

          generic_fragment(exposure, 'formatter-changes-type',
                           "field `#{exposure.attribute}` uses a custom formatter whose output " \
                           'type is unknown; declare documentation: { type: ... } or { schema: ... }')
        end

        def delegator_fragment(exposure)
          declared = documentation_type_fragment(exposure)
          return declared if declared

          generic_fragment(exposure, 'delegator-no-type',
                           "field `#{exposure.attribute}` has no declared type")
        end

        def documentation_type_fragment(exposure)
          doc = documentation_hash(exposure)
          doc && fragment_from_documentation(doc)
        end

        def generic_fragment(exposure, code, message = nil)
          message ||= "field `#{exposure.attribute}` output type cannot be derived statically"
          @warnings << warning(exposure, code, message)
          {}
        end

        def collection?(exposure)
          doc = documentation_hash(exposure)
          return collection_from_doc(doc) if doc

          # Static default is a single represented object.
          false
        end

        def collection_from_doc(doc)
          return true if doc[:is_collection] == true
          return false if doc.key?(:is_collection)
          return true if doc[:type].is_a?(String) && doc[:type].end_with?('[]')

          doc[:type] == Array
        end

        def using_not_entity_note(exposure)
          "field `#{exposure.attribute}` maps to #{exposure.using_class.inspect}, " \
            'which is not a Grape::Entity'
        end
      end
    end
  end
end
