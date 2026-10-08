# frozen_string_literal: true

require 'spec_helper'
require 'support/schema_validator'

module JsonSchemaSpec
  class Address
    attr_reader :city, :zip

    def initialize(city:, zip:)
      @city = city
      @zip = zip
    end
  end
  User = Struct.new(:id, :name, :address, :friends, :manager, :tags, :score,
                    :nickname, keyword_init: true) do
    def admin?
      false
    end
  end
  Node = Struct.new(:value, :children, keyword_init: true)
  Place = Struct.new(:name, :lat, :lng, :kind, keyword_init: true)

  class AddressEntity < Grape::Entity
    expose :city, documentation: { type: 'String', required: true }
    expose :zip, documentation: { type: 'String' }
  end

  class UserEntity < Grape::Entity
    root 'users', 'user'

    expose :id, documentation: { type: 'Integer', required: true }
    expose :name, as: :full_name, documentation: { type: 'String', desc: 'Display name' }
    expose :email, if: { type: :full }, documentation: { type: 'String' }
    expose :token, if: ->(user, _) { user.admin? }, documentation: { type: 'String' }
    expose :address, using: AddressEntity
    expose :friends, using: UserEntity, documentation: { is_collection: true }
    expose :manager, using: UserEntity
    expose :tags, documentation: { type: 'String[]' }
    expose :score, documentation: { type: 'Float', nullable: true }
    expose :nickname, expose_nil: false, documentation: { type: 'String' }
  end

  class NodeEntity < Grape::Entity
    expose :value, documentation: { type: 'Integer', required: true }
    expose :children, using: NodeEntity, documentation: { is_collection: true }
  end

  class CoordinatesEntity < Grape::Entity
    expose :lat, documentation: { type: 'Float', required: true }
    expose :lng, documentation: { type: 'Float' }
  end

  class PlaceEntity < Grape::Entity
    expose :name, documentation: { type: 'String', required: true }
    expose :coordinates, merge: true, using: CoordinatesEntity
    expose :dynamic, as: proc { object.kind }, documentation: { type: 'String' }
    expose :shouted do |place, _|
      place.name.to_s.upcase
    end
  end

  class ListEntity < Grape::Entity
    present_collection true
    root 'lists', 'list'

    expose :items, using: AddressEntity
    expose :version, documentation: { type: 'String', required: true }
  end
end

describe Grape::Entity, '.json_schema' do
  def user_object
    JsonSchemaSpec::User.new(
      id: 7,
      name: 'Zoe',
      address: JsonSchemaSpec::Address.new(city: 'Berlin', zip: '10115'),
      friends: [],
      manager: nil,
      tags: %w[red blue],
      score: 1.5,
      nickname: 'z'
    )
  end

  describe 'document shape' do
    subject(:schema) { JsonSchemaSpec::UserEntity.json_schema }
    let(:root_def) do
      ref = schema.key?('$ref') ? schema['$ref'] : schema.dig('properties', 'user', '$ref')
      schema['$defs'][ref.sub('#/$defs/', '')]
    end
    let(:properties) { root_def['properties'] }

    it 'emits a draft 2020-12 document with a root ref' do
      expect(schema['$schema']).to eq('https://json-schema.org/draft/2020-12/schema')
      expect(schema.dig('properties', 'user', '$ref')).to start_with('#/$defs/')
      expect(schema['$defs'].keys).to include(a_string_ending_with('UserEntity'),
                                              a_string_ending_with('AddressEntity'))
    end

    it 'builds properties from output aliases' do
      expect(properties).to include('id', 'full_name', 'address', 'friends', 'tags', 'score')
      expect(properties).not_to include('name')
      expect(properties['full_name']['description']).to eq('Display name')
    end

    it 'maps declared documentation types' do
      expect(properties['id']['type']).to eq('integer')
      expect(properties['full_name']['type']).to eq('string')
      expect(properties['tags']).to eq('type' => 'array', 'items' => { 'type' => 'string' })
    end

    it 'reuses required declarations' do
      expect(root_def['required']).to eq(['id'])
      address_name = schema['$defs'].keys.find { |name| name.end_with?('AddressEntity') }
      expect(schema['$defs'][address_name]['required']).to eq(['city'])
    end

    it 'expands nullable declarations' do
      expect(properties['score']['type']).to eq(%w[number null])
    end

    it 'marks every conditional field optional with a note' do
      required = root_def['required']
      expect(required).not_to include('email')
      expect(required).not_to include('token')
      expect(properties['email']['x-grape-entity-note']).to include('if { type: :full }')
      expect(properties['token']['x-grape-entity-note']).to include('if <proc>')
    end

    it 'notes fields that disappear when nil' do
      note = properties['nickname']['x-grape-entity-note']
      expect(note).to include('unless <proc>')
    end
  end

  describe 'using and collections' do
    subject(:schema) { JsonSchemaSpec::UserEntity.json_schema }
    let(:root_def) do
      ref = schema.dig('properties', 'user', '$ref')
      schema['$defs'][ref.sub('#/$defs/', '')]
    end
    let(:properties) { root_def['properties'] }

    it 'references nested entities' do
      address_name = schema['$defs'].keys.find { |name| name.end_with?('AddressEntity') }
      expect(properties['address'])
        .to eq('oneOf' => [{ '$ref' => "#/$defs/#{address_name}" }, { 'type' => 'null' }])
    end

    it 'wraps declared collections in arrays' do
      self_ref = { '$ref' => schema.dig('properties', 'user', '$ref') }
      expect(properties['friends'])
        .to eq('type' => %w[array null],
               'items' => { 'oneOf' => [self_ref, { 'type' => 'null' }] })
    end

    it 'defaults an undeclared using exposure to a single object' do
      self_ref = { '$ref' => schema.dig('properties', 'user', '$ref') }
      expect(properties['manager'])
        .to eq('oneOf' => [self_ref, { 'type' => 'null' }])
    end
  end

  describe 'recursion' do
    subject(:schema) { JsonSchemaSpec::NodeEntity.json_schema }

    it 'defines the entity once and links back with $ref' do
      expect(schema['$defs'].keys.size).to eq(1)
      node_name = schema['$defs'].keys.first
      expect(node_name).to end_with('NodeEntity')
      children = schema['$defs'][node_name]['properties']['children']
      expect(children['items']['oneOf'].first).to eq('$ref' => "#/$defs/#{node_name}")
    end
  end

  describe 'merge fields' do
    subject(:schema) { JsonSchemaSpec::PlaceEntity.json_schema }
    let(:place) do
      name = schema['$defs'].keys.find { |key| key.end_with?('PlaceEntity') }
      schema['$defs'][name]
    end

    it 'flattens merged entity properties and required into the parent' do
      expect(place['properties']).to include('name', 'lat', 'lng')
      expect(place['properties']).not_to include('coordinates')
      expect(place['required']).to eq(%w[name lat])
    end

    it 'reports dynamic keys instead of inventing property names' do
      expect(place['additionalProperties']).to be(true)
      expect(place['properties']).not_to include('dynamic')
      warning = schema['x-grape-entity']['warnings'].find { |w| w['code'] == 'dynamic-key' }
      expect(warning['attribute']).to eq('dynamic')
    end

    it 'does not guess block value types' do
      expect(place['properties']['shouted']).to eq({})
      warning = schema['x-grape-entity']['warnings'].find { |w| w['attribute'] == 'shouted' }
      expect(warning['code']).to eq('block-value')
    end

    it 'uses an explicit schema to describe dynamic-key values' do
      entity = Class.new(Grape::Entity) do
        expose :name, documentation: { type: 'String', required: true }
        expose :labels, as: proc { object.kind }, documentation: {
          schema: { 'type' => 'object', 'additionalProperties' => { 'type' => 'string' } }
        }
      end
      definition = entity.json_schema['$defs'].values.first
      expect(definition['properties']).not_to include('labels')
      expect(definition['additionalProperties']).to eq('type' => 'string')
      expect(entity.json_schema['x-grape-entity']['warnings']).to be_empty
    end
  end

  describe 'formatters' do
    it 'reports when a custom formatter changes the type' do
      entity = Class.new(Grape::Entity) do
        format_with(:upcase) { |value| value.to_s.upcase }
        expose :name, format_with: :upcase
      end
      schema = entity.json_schema
      expect(schema['$defs'].values.first['properties']['name']).to eq({})
      expect(schema['x-grape-entity']['warnings'].map { |w| w['code'] })
        .to include('formatter-changes-type')
    end

    it 'uses an explicit documentation type for formatted fields' do
      entity = Class.new(Grape::Entity) do
        format_with(:upcase) { |value| value.to_s.upcase }
        expose :name, format_with: :upcase, documentation: { type: 'String' }
      end
      schema = entity.json_schema
      expect(schema['$defs'].values.first['properties']['name']).to eq('type' => 'string')
      expect(schema['x-grape-entity']['warnings']).to be_empty
    end

    it 'honors explicit schema declarations' do
      entity = Class.new(Grape::Entity) do
        expose :code, documentation: { schema: { 'type' => 'string', 'pattern' => '^[a-z]+$' } }
      end
      schema = entity.json_schema
      expect(schema['$defs'].values.first['properties']['code'])
        .to eq('type' => 'string', 'pattern' => '^[a-z]+$')
    end
  end

  describe 'inheritance' do
    it 'includes parent and child exposures in the final structure' do
      parent = Class.new(Grape::Entity) do
        expose :id, documentation: { type: 'Integer', required: true }
      end
      child = Class.new(parent) do
        expose :flag, documentation: { type: 'Boolean' }
      end

      schema = child.json_schema
      properties = schema['$defs'].values.first['properties']
      expect(properties.keys).to eq(%w[id flag])
      expect(schema['$defs'].values.first['required']).to eq(['id'])
    end
  end

  describe 'only/except projections' do
    def root_definition(schema)
      ref = schema.dig('properties', 'user', '$ref')
      schema['$defs'][ref.sub('#/$defs/', '')]
    end

    it 'keeps only the projected fields' do
      schema = JsonSchemaSpec::UserEntity.json_schema(only: %i[id address])
      root_def = root_definition(schema)
      expect(root_def['properties'].keys).to eq(%w[id address])
      expect(root_def['required']).to eq(['id'])
    end

    it 'projects nested using exposures' do
      schema = JsonSchemaSpec::UserEntity.json_schema(only: [:id, { address: [:city] }])
      root_def = root_definition(schema)
      address_ref = root_def['properties']['address']['oneOf'].first['$ref']
      address_def = schema['$defs'][address_ref.sub('#/$defs/', '')]
      expect(address_def['properties'].keys).to eq(['city'])
    end

    it 'supports except projections' do
      schema = JsonSchemaSpec::UserEntity.json_schema(except: %i[tags score])
      root_def = root_definition(schema)
      expect(root_def['properties'].keys).not_to include('tags', 'score')
    end

    it 'keeps a key while excluding nested fields via an except hash' do
      schema = JsonSchemaSpec::UserEntity.json_schema(except: [{ address: [:zip] }])
      root_def = root_definition(schema)
      expect(root_def['properties'].keys).to include('address')
      address_ref = root_def['properties']['address']['oneOf'].first['$ref']
      address_def = schema['$defs'][address_ref.sub('#/$defs/', '')]
      expect(address_def['properties'].keys).to eq(['city'])
    end
  end

  describe 'roots and present_collection' do
    it 'wraps single and collection output according to root declarations' do
      single = JsonSchemaSpec::UserEntity.json_schema
      collection = JsonSchemaSpec::UserEntity.json_schema(collection: true)

      expect(single['properties'].keys).to eq(['user'])
      expect(single['required']).to eq(['user'])
      expect(collection['properties'].keys).to eq(['users'])
      expect(collection.dig('properties', 'users', 'type')).to eq('array')
    end

    it 'can disable the root wrapper' do
      schema = JsonSchemaSpec::UserEntity.json_schema(root: false)
      expect(schema).to have_key('$ref')
      expect(schema).not_to have_key('properties')
    end

    it 'reflects present_collection as one object with an array accessor' do
      schema = JsonSchemaSpec::ListEntity.json_schema(collection: true)
      list_def = schema['$defs'][schema['$ref'].sub('#/$defs/', '')]
      items = list_def['properties']['items']
      expect(items['type']).to eq(%w[array null])
      expect(list_def['required']).to eq(['version'])
    end
  end

  describe 'conformance against actual representations' do
    it 'validates a plain representation (single and collection)' do
      object = user_object
      single_schema = JsonSchemaSpec::UserEntity.json_schema
      collection_schema = JsonSchemaSpec::UserEntity.json_schema(collection: true)

      single = JSON.parse(JSON.generate(JsonSchemaSpec::UserEntity.represent(object, serializable: true)))
      collection = JSON.parse(JSON.generate(JsonSchemaSpec::UserEntity.represent([object], serializable: true)))

      expect(SchemaValidator.new(single_schema).errors(single)).to be_empty
      expect(SchemaValidator.new(collection_schema).errors(collection)).to be_empty
    end

    it 'validates a recursive representation' do
      node = JsonSchemaSpec::Node.new(
        value: 1,
        children: [
          JsonSchemaSpec::Node.new(value: 2, children: []),
          JsonSchemaSpec::Node.new(value: 3, children: [JsonSchemaSpec::Node.new(value: 4)])
        ]
      )
      schema = JsonSchemaSpec::NodeEntity.json_schema
      data = JSON.parse(JSON.generate(JsonSchemaSpec::NodeEntity.represent(node, serializable: true)))
      expect(SchemaValidator.new(schema).errors(data)).to be_empty
    end

    it 'validates a projected representation' do
      object = user_object
      only = [:id, { address: [:city] }]
      schema = JsonSchemaSpec::UserEntity.json_schema(only: only)
      data = JSON.parse(
        JSON.generate(
          JsonSchemaSpec::UserEntity.represent(object, serializable: true, only: only)
        )
      )
      expect(SchemaValidator.new(schema).errors(data)).to be_empty
    end
  end
end
