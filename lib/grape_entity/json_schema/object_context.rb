# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Accumulates an object fragment while exposures are walked.
      class ObjectContext
        attr_reader :properties, :required, :notes
        attr_writer :additional_properties

        def initialize
          @properties = {}
          @required = []
          @notes = []
          @additional_properties = false
        end

        def add_property(key, schema, required)
          @properties[key.to_s] = schema
          @required << key.to_s if required
        end

        def add_dynamic(note)
          @additional_properties = true
          add_note(note)
        end

        def add_note(note)
          @notes << note
        end

        def to_fragment
          fragment = { 'type' => 'object', 'properties' => @properties }
          fragment['required'] = @required unless @required.empty?
          fragment['additionalProperties'] = @additional_properties
          fragment['x-grape-entity-notes'] = @notes unless @notes.empty?
          fragment
        end
      end
    end
  end
end
