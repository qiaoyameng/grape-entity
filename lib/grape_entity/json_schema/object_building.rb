# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Builds object fragments from a list of exposures, applying only/
      # except projections, required detection, dynamic-key handling and
      # merge flattening (see Grape::Entity::JsonSchema::Merging).
      module ObjectBuilding
        private

        def object_fragment(exposures, only, except, registry_key = nil)
          context = ObjectContext.new
          exposures.each { |exposure| add_exposure(exposure, context, only, except, registry_key) }
          context.to_fragment
        end

        def add_exposure(exposure, context, only, except, registry_key)
          if exposure.dynamic_key?
            add_dynamic_exposure(exposure, context)
            return
          end

          key = exposure.static_key
          return unless key_allowed?(key, only, except)

          child_only = projection_for(key, only)
          child_except = projection_for(key, except)
          return merge_exposure(exposure, context, child_only, child_except, registry_key) if exposure.for_merge

          context.add_property(key, property_fragment(exposure, child_only, child_except),
                               structurally_required?(exposure))
        end

        def add_dynamic_exposure(exposure, context)
          explicit = explicit_schema(exposure)
          if explicit
            explicit = stringify_keys(explicit)
            context.additional_properties = explicit.fetch('additionalProperties', true)
            context.add_note(
              "field `#{exposure.attribute}` uses a dynamic (`as:` proc) key; " \
              'properties follow the explicit schema declaration'
            )
          else
            context.add_dynamic(dynamic_note(exposure))
            @warnings << warning(exposure, 'dynamic-key', dynamic_note(exposure))
          end
        end

        def key_allowed?(key, only, except)
          return true if key.nil?

          return false unless allowed_projection?(only, key)

          # `except: { a: [:b] }` keeps `a` but drops `b` inside it; only
          # `except: :a` (marked true) removes the key at this level.
          !(except.is_a?(Hash) && except[key] == true)
        end

        def allowed_projection?(projection, key)
          return true if projection.nil?
          return projection.include?(key) if projection.is_a?(Array)

          projection.key?(key)
        end

        def projection_for(key, projection)
          return nil unless projection.is_a?(Hash)

          value = projection[key]
          value.is_a?(Hash) ? value : nil
        end

        def structurally_required?(exposure)
          return false if exposure.conditional? || exposure.dynamic_key? || exposure.omit_nil?

          (doc = documentation_hash(exposure)) && doc[:required] == true
        end

        def dynamic_note(exposure)
          "field `#{exposure.attribute}` uses a dynamic (`as:` proc) key; property names " \
            'cannot be derived statically'
        end
      end
    end
  end
end
