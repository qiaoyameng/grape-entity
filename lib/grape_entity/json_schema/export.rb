# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Explicit JSON Schema export entry point mixed into Grape::Entity.
      module Export
        # Exports a JSON Schema describing the entity's serialized output.
        #
        # Unlike {Grape::Entity.documentation}, which returns the raw field
        # descriptions passed via `documentation:`, the schema reuses every
        # statically declared exposure detail — documentation type, required
        # fields, nullable fields, `using:` nested entities and collection
        # declarations — and builds `properties` from the output aliases.
        #
        # Recursive entities are emitted once under `$defs` and referenced
        # with `$ref`; object getters and conditional Procs are never
        # evaluated, so conditionally exposed fields are always marked
        # optional with a note in `x-grape-entity`. Fields whose shape cannot
        # be known statically (merged block values, dynamic keys, formatter-
        # changed types) come from an explicit `documentation: { schema: }`
        # declaration or are reported in `x-grape-entity` warnings rather
        # than receiving a misleading precise type.
        #
        # @option options :collection [Boolean] describe a represented collection
        # @option options :only [Array, Hash] projection, as given to `represent`
        # @option options :except [Array, Hash] projection, as given to `represent`
        # @option options :root [:auto, String, Symbol, false, nil] root wrapper
        # @option options :present_collection [Boolean] override the class flag
        # @option options :id [String] optional JSON Schema `$id`
        # @option options :title [String] optional schema title
        # @return [Hash] a JSON Schema document with string keys
        def json_schema(**options)
          JsonSchema.build(self, **options)
        end

        # Whether this entity presents a whole collection through a single
        # collection accessor (see Grape::Entity.present_collection).
        def present_collection?
          @present_collection == true
        end

        # The collection accessor name configured with .present_collection.
        def collection_name
          @collection_name || :items
        end
      end
    end
  end
end
