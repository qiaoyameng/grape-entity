# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Walks the exposure tree of one or more entity classes and produces a
      # self-contained JSON Schema document with stable $defs/$ref.
      class Builder
        include Roots
        include Registry
        include ObjectBuilding
        include Merging
        include ExposureFragment
        include DocumentationSupport
        include Helpers

        attr_reader :warnings

        def initialize(entity, **opts)
          @entity = entity
          @collection = opts.fetch(:collection, false)
          @only = JsonSchema.normalize_projection(opts[:only])
          @except = JsonSchema.normalize_projection(opts[:except])
          @root_option = opts.fetch(:root, :auto)
          @present_collection_option = opts[:present_collection]
          @id = opts[:id]
          @title = opts[:title]

          @warnings = []
          @def_names = {}
          @fragments = {}
          @building = Set.new
          @anonymous = 0
          @pending_merges = []
          @collection_merges = {}
        end

        def build
          inner = entity_ref_schema(@entity, @only, @except, @collection && !present_collection?)
          schema = wrap_root(inner)

          document = { '$schema' => JsonSchema::DRAFT, '$defs' => @fragments }
          document['$id'] = @id if @id
          document['title'] = @title if @title
          document.merge!(schema)

          process_pending_merges

          document['x-grape-entity'] = {
            'entity' => @entity.name,
            'collection' => @collection,
            'only' => @only,
            'except' => @except,
            'warnings' => @warnings
          }
          document
        end
      end
    end
  end
end
