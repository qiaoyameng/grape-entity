# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Tracks entity classes as stable $defs and builds their fragments,
      # breaking recursive references with $ref.
      module Registry
        private

        def entity_ref_schema(entity, only, except, force_array)
          schema = entity_ref(entity, only, except)
          force_array ? array_of(schema) : schema
        end

        def array_of(item_schema)
          { 'type' => 'array', 'items' => item_schema }
        end

        def entity_ref(entity, only, except)
          signature = JsonSchema.projection_signature(only, except)
          registry_key = [entity, signature]
          name = def_name_for(entity, only, except)

          unless @def_names.key?(registry_key)
            @def_names[registry_key] = name
            build_entity_fragment(entity, only, except, registry_key)
          end

          { '$ref' => "#/$defs/#{name}" }
        end

        def def_name_for(entity, only, except)
          base =
            if entity.name && !entity.name.empty?
              entity.name.gsub(/[^A-Za-z0-9_.-]/, '_')
            else
              "anonymous_entity_#{@anonymous += 1}"
            end
          return base unless only || except

          "#{base}-#{JsonSchema.projection_signature(only, except)}"
        end

        def build_entity_fragment(entity, only, except, registry_key)
          return mark_using_target(registry_key) unless entity.respond_to?(:root_exposures)
          return seed_recursive_fragment(registry_key) if @building.include?(registry_key)

          @building.add(registry_key)
          fragment = object_fragment(entity.root_exposures, only, except, registry_key)
          @building.delete(registry_key)

          fragment = collection_merge_fragment(fragment) if @collection_merges[registry_key]
          @fragments[@def_names[registry_key]] = fragment
        end

        def mark_using_target(registry_key)
          name = @def_names[registry_key]
          @fragments[name] = {}
          @warnings << {
            'attribute' => nil,
            'code' => 'using-not-entity',
            'message' => '`using` target is not a Grape::Entity; output type is unknown'
          }
        end

        def seed_recursive_fragment(registry_key)
          name = @def_names[registry_key]
          @fragments[name] ||= { 'type' => 'object' }
        end

        def collection_merge_fragment(fragment)
          { 'oneOf' => [fragment, { 'type' => 'array', 'items' => {} }] }
        end
      end
    end
  end
end
