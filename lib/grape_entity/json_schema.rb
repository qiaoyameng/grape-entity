# frozen_string_literal: true

require 'digest'
require 'json'

module Grape
  class Entity
    # Builds a JSON Schema (draft 2020-12) describing the *output* of an
    # Entity. Unlike {Grape::Entity.documentation}, which returns the raw
    # `documentation:` field descriptions, this inspects declared exposures
    # statically and reuses their declared type, required/nil metadata,
    # `using:` nested entities and collection information.
    #
    # Object getters and conditional Procs are never executed. When the
    # output shape cannot be known statically the field is described
    # conservatively and the reason is recorded under `x-grape-entity`.
    module JsonSchema
      DRAFT = 'https://json-schema.org/draft/2020-12/schema'
      NOTE_KEY = 'x-grape-entity-note'

      module_function

      def build(entity, **opts)
        Builder.new(entity, **opts).build
      end

      # Mirrors Grape::Entity::Options#build_symbolized_hash, recursively,
      # so projection signatures stay stable regardless of key type.
      def normalize_projection(value)
        case value
        when Hash
          value.each_with_object({}) do |(key, nested), memo|
            memo[key.to_sym] = normalize_projection(nested)
          end
        when Array
          value.each_with_object({}) do |item, memo|
            item.is_a?(Hash) ? memo.merge!(normalize_projection(item)) : memo[item.to_sym] = true
          end
        when nil then nil
        else value.to_sym
        end
      end

      def projection_signature(only, except)
        Digest::SHA256.hexdigest(::JSON.generate(only: only, except: except))[0, 8]
      end

      def fragment_for_type(type)
        TypeMap.fragment_for_type(type)
      end

      def nullable(fragment)
        return fragment if fragment.nil? || fragment.empty?

        types = Array(fragment['type'])
        return fragment if types.include?('null')

        fragment = fragment.dup
        fragment['type'] = types + ['null']
        fragment
      end

      def describe_condition(condition)
        Conditions.describe_condition(condition)
      end
    end
  end
end
