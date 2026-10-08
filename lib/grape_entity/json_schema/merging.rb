# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Handles `merge: true` exposures, flattening their declared shape into
      # the parent object fragment.
      module Merging
        private

        def merge_exposure(exposure, context, only, except, registry_key)
          source = exposure.is_a?(Exposure::RepresentExposure) ? exposure : nil
          if source && source.using_class.respond_to?(:root_exposures)
            merge_entity_exposure(source, context, only, except, registry_key)
          elsif (explicit = explicit_schema(exposure))
            merge_explicit_exposure(exposure, explicit, context)
          else
            note = underivable_merge_note(exposure)
            context.add_note(note)
            @warnings << warning(exposure, 'merge-underivable', note)
          end
        end

        def merge_entity_exposure(exposure, context, only, except, registry_key)
          if collection?(exposure)
            note = collection_merge_note(exposure)
            context.add_note(note)
            @warnings << warning(exposure, 'merge-collection-shape', note)
            @collection_merges[registry_key] = true if registry_key
            return
          end

          queue_entity_merge(exposure.using_class, context, only, except)
          flatten_entity(exposure.using_class, context.properties, context.required, only, except)
        end

        def merge_explicit_exposure(exposure, explicit, context)
          explicit = stringify_keys(explicit)
          if explicit['properties'].is_a?(Hash)
            flatten_explicit(explicit, context.properties, context.required)
          else
            note = "field `#{exposure.attribute}` is merged with a non-object explicit schema; " \
                   'the parent shape cannot be derived statically'
            context.add_note(note)
            @warnings << warning(exposure, 'merge-explicit-shape', note)
          end
        end

        def queue_entity_merge(entity, context, only, except)
          @pending_merges << {
            entity: entity,
            properties: context.properties,
            required: context.required,
            only: only,
            except: except
          }
        end

        def flatten_entity(entity, properties, required, only, except)
          signature = JsonSchema.projection_signature(only, except)
          registry_key = [entity, signature]
          name = def_name_for(entity, only, except)
          unless @def_names.key?(registry_key)
            @def_names[registry_key] = name
            build_entity_fragment(entity, only, except, registry_key)
          end

          merge_fragment_properties(@fragments[name] || { 'type' => 'object' }, properties, required)
        end

        def merge_fragment_properties(fragment, properties, required)
          object_fragment = fragment['oneOf'] ? fragment['oneOf'].first : fragment
          (object_fragment['properties'] || {}).each do |key, schema|
            properties[key] = schema unless properties.key?(key)
          end
          (object_fragment['required'] || []).each { |key| required << key unless required.include?(key) }
        end

        def flatten_explicit(schema, properties, required)
          schema['properties'].each do |key, prop_schema|
            properties[key] = prop_schema unless properties.key?(key)
          end
          Array(schema['required']).each { |key| required << key unless required.include?(key) }
        end

        def process_pending_merges
          @pending_merges.each do |job|
            flatten_entity(job[:entity], job[:properties], job[:required], job[:only], job[:except])
          end
        end

        def collection_merge_note(exposure)
          "field `#{exposure.attribute}` merges a collection into the parent; the output " \
            'becomes an array at runtime and cannot be described as an object schema'
        end

        def underivable_merge_note(exposure)
          "field `#{exposure.attribute}` is merged into the parent but its output type cannot " \
            'be derived statically (block/formatter/delegator value); declare ' \
            'documentation: { schema: ... } for a precise schema'
        end
      end
    end
  end
end
