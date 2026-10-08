# frozen_string_literal: true

# Minimal JSON Schema (draft 2020-12 subset) validator used to check that
# actual entity representations conform to the exported schemas. Supports
# $ref/$defs, type (including nullable type arrays), properties/required/
# additionalProperties, items and oneOf. Descriptions/notes are ignored.
class SchemaValidator
  def initialize(document)
    @document = document
  end

  def errors(data, schema = @document, path = '$')
    return errors(data, resolve_ref(schema), path) if schema.key?('$ref')
    return one_of_errors(data, schema, path) if schema.key?('oneOf')

    errors = type_errors(data, schema, path)
    errors.concat(container_errors(data, schema, path))
    errors
  end

  private

  def resolve_ref(schema)
    name = schema['$ref'].sub('#/$defs/', '')
    @document['$defs'][name]
  end

  def one_of_errors(data, schema, path)
    matched = schema['oneOf'].any? { |candidate| errors(data, candidate, path).empty? }
    matched ? [] : ["#{path}: matches no oneOf branch"]
  end

  def type_errors(data, schema, path)
    types = Array(schema['type'])
    return [] if types.empty? || types.any? { |type| type_match?(type, data) }

    ["#{path}: expected #{types.join('|')}, got #{data.class}"]
  end

  def container_errors(data, schema, path)
    case data
    when Hash
      object_errors(data, schema, path)
    when Array
      array_errors(data, schema, path)
    else
      []
    end
  end

  def object_errors(data, schema, path)
    properties = schema['properties'] || {}
    errors = []
    Array(schema['required']).each do |key|
      errors << "#{path}: missing #{key}" unless data.key?(key)
    end
    if schema['additionalProperties'] == false
      data.each_key { |key| errors << "#{path}: extra #{key}" unless properties.key?(key) }
    end
    properties.each do |key, subschema|
      errors.concat(errors(data[key], subschema, "#{path}.#{key}")) if data.key?(key)
    end
    errors
  end

  def array_errors(data, schema, path)
    return [] unless schema['items']

    data.flat_map.with_index { |item, index| errors(item, schema['items'], "#{path}[#{index}]") }
  end

  def type_match?(type, data)
    case type
    when 'object' then data.is_a?(Hash)
    when 'array' then data.is_a?(Array)
    when 'string' then data.is_a?(String) || data.is_a?(Symbol)
    when 'integer' then data.is_a?(Integer)
    when 'number' then data.is_a?(Numeric)
    when 'boolean' then [true, false].include?(data)
    when 'null' then data.nil?
    else true
    end
  end
end
