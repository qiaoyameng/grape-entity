# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Documentation `type:` value -> JSON Schema fragment conversion.
      module TypeMap
        MAP = {
          'Integer' => { 'type' => 'integer' },
          'Float' => { 'type' => 'number' },
          'BigDecimal' => { 'type' => 'number' },
          'Numeric' => { 'type' => 'number' },
          'String' => { 'type' => 'string' },
          'Symbol' => { 'type' => 'string' },
          'Boolean' => { 'type' => 'boolean' },
          'Date' => { 'type' => 'string', 'format' => 'date' },
          'DateTime' => { 'type' => 'string', 'format' => 'date-time' },
          'Time' => { 'type' => 'string', 'format' => 'date-time' },
          'ISO8601' => { 'type' => 'string', 'format' => 'date-time' },
          'JSON' => {}
        }.freeze

        module_function

        def fragment_for_type(type)
          case type
          when nil then nil
          when Hash then type.transform_keys(&:to_s)
          when Array then fragment_for_array_type(type)
          when String, Symbol then fragment_for_name(type.to_s)
          when Class then fragment_for_class(type)
          end
        end

        def fragment_for_array_type(type)
          mapped = type.map { |item| fragment_for_type(item) }.compact
          return nil if mapped.empty?
          return mapped.first if mapped.size == 1

          { 'oneOf' => mapped }
        end

        def fragment_for_name(name)
          return MAP[name] if MAP.key?(name)

          bare = name.delete_suffix('[]')
          if MAP.key?(bare)
            { 'type' => 'array', 'items' => MAP[bare] }
          elsif %w[integer number string boolean array object null].include?(name.downcase)
            { 'type' => name.downcase }
          end
        end

        def fragment_for_class(klass)
          case klass
          when ->(k) { [String, Symbol].include?(k) } then MAP['String']
          when ->(k) { k == Integer } then MAP['Integer']
          when ->(k) { [Float, BigDecimal].include?(k) } then MAP['Float']
          when ->(k) { k == Date } then MAP['Date']
          when ->(k) { [Time, DateTime, ActiveSupport::TimeWithZone].include?(k) } then MAP['Time']
          when ->(k) { [TrueClass, FalseClass].include?(k) } then MAP['Boolean']
          when ->(k) { [Hash, ActiveSupport::HashWithIndifferentAccess].include?(k) }
            { 'type' => 'object' }
          when ->(k) { k == Array } then { 'type' => 'array' }
          end
        end
      end
    end
  end
end
