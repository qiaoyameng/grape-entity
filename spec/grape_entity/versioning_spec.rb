# frozen_string_literal: true

describe Grape::Entity, 'versioning' do
  let(:child_class) do
    Class.new do
      attr_accessor :legacy, :current, :future

      def initialize(legacy:, current:, future:)
        @legacy = legacy
        @current = current
        @future = future
      end
    end
  end

  let(:object) do
    model_class = Class.new do
      attr_accessor :legacy, :current, :future, :name, :child
    end
    model_class.new.tap do |model|
      model.legacy = 'legacy'
      model.current = 'current'
      model.future = 'future'
      model.name = 'name'
      model.child = child_class.new(legacy: 'child-legacy', current: 'child-current', future: 'child-future')
    end
  end

  def build_entity
    Class.new(Grape::Entity) do
      expose :legacy, until: '2'
      expose :current, since: '2', until: '3'
      expose :future, since: '3'
    end
  end

  it 'compares numeric version segments rather than strings' do
    entity = Class.new(Grape::Entity) do
      expose :current, until: '2.10'
      expose :future, since: '2.10'
    end

    expect(entity.represent(object, version: '2.9', serializable: true)).to eq(current: 'current')
    expect(entity.represent(object, version: '2.10', serializable: true)).to eq(future: 'future')
  end

  it 'uses inclusive since and exclusive until boundaries' do
    entity = build_entity

    expect(entity.represent(object, version: '1.9', serializable: true)).to eq(legacy: 'legacy')
    expect(entity.represent(object, version: '2', serializable: true)).to eq(current: 'current')
    expect(entity.represent(object, version: '2.99', serializable: true)).to eq(current: 'current')
    expect(entity.represent(object, version: '3', serializable: true)).to eq(future: 'future')
  end

  it 'accepts a leading v prefix' do
    entity = Class.new(Grape::Entity) do
      expose :current, until: '2.10'
      expose :future, since: '2.10'
    end

    expect(entity.represent(object, version: 'v2.10', serializable: true)).to eq(future: 'future')
  end

  it 'does not get excluded fields while evaluating conditions' do
    calls = []
    object.define_singleton_method(:legacy) do
      calls << :legacy_getter
      'legacy'
    end

    entity = Class.new(Grape::Entity) do
      expose :legacy, until: '2', if: lambda { |item, _options|
        calls << :legacy_condition
        item.legacy
      }
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq({})
    expect(calls).to eq([])
  end

  it 'does not call getters or formatters for excluded fields' do
    calls = []
    object.define_singleton_method(:legacy) do
      calls << :legacy_getter
      'legacy'
    end

    entity = Class.new(Grape::Entity) do
      format_with(:trace) do |value|
        calls << :legacy_formatter
        value
      end
      expose :legacy, until: '2', format_with: :trace
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq({})
    expect(calls).to eq([])
  end

  it 'does not evaluate blocks for excluded fields' do
    calls = []
    entity = Class.new(Grape::Entity) do
      expose :legacy, until: '2' do |_item, _options|
        calls << :legacy_block
        'legacy'
      end
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq({})
    expect(calls).to eq([])
  end

  it 'applies version filtering to nested exposures before nested conditions' do
    calls = []
    object.define_singleton_method(:legacy) do
      calls << :nested_legacy_getter
      'legacy'
    end

    entity = Class.new(Grape::Entity) do
      expose :details do
        expose :legacy, until: '2', if: lambda { |item, _options|
          calls << :condition
          item.legacy
        }
      end
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq(details: {})
    expect(calls).to eq([])
  end

  it 'omits a versioned nesting exposure and its children entirely' do
    calls = []
    object.define_singleton_method(:legacy) do
      calls << :nested_legacy_getter
      'legacy'
    end

    entity = Class.new(Grape::Entity) do
      expose :details, until: '2' do
        expose :legacy, if: lambda { |item, _options|
          calls << :condition
          item.legacy
        }
      end
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq({})
    expect(calls).to eq([])
  end

  it 'inherits the parent version in nested entities' do
    child_entity = build_entity
    entity = Class.new(Grape::Entity) do
      expose :child, using: child_entity
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq(child: { current: 'child-current' })
  end

  it 'keeps parent and child value counts isolated while interleaving versions' do
    counter_class = Class.new do
      attr_reader :child, :legacy_count, :current_count, :future_count

      def initialize(child = nil)
        @child = child
        @legacy_count = 0
        @current_count = 0
        @future_count = 0
      end

      def legacy
        @legacy_count += 1
        'legacy'
      end

      def current
        @current_count += 1
        'current'
      end

      def future
        @future_count += 1
        'future'
      end
    end

    parent = counter_class.new(counter_class.new)
    child_entity = build_entity
    entity = Class.new(Grape::Entity) do
      expose :legacy, until: '2'
      expose :current, since: '2', until: '3'
      expose :future, since: '3'
      expose :child, using: child_entity
    end

    expect(entity.represent(parent, version: '1', serializable: true)).to eq(
      legacy: 'legacy',
      child: { legacy: 'legacy' }
    )
    expect(entity.represent(parent, version: '2', serializable: true)).to eq(
      current: 'current',
      child: { current: 'current' }
    )
    expect(entity.represent(parent, version: '1', serializable: true)).to eq(
      legacy: 'legacy',
      child: { legacy: 'legacy' }
    )

    expect(parent.legacy_count).to eq(2)
    expect(parent.current_count).to eq(1)
    expect(parent.future_count).to eq(0)
    expect(parent.child.legacy_count).to eq(2)
    expect(parent.child.current_count).to eq(1)
    expect(parent.child.future_count).to eq(0)
  end

  it 'allows explicit nested version mapping' do
    child_entity = build_entity
    entity = Class.new(Grape::Entity) do
      expose :child, using: child_entity, version_mapping: { '2' => '1' }
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq(child: { legacy: 'child-legacy' })
  end

  it 'allows callable nested version mapping' do
    child_entity = build_entity
    entity = Class.new(Grape::Entity) do
      expose :child, using: child_entity, version_mapping: ->(version) { Grape::Entity::Version.cast(version).segments.first - 1 }
    end

    expect(entity.represent(object, version: '2', serializable: true)).to eq(child: { legacy: 'child-legacy' })
  end

  it 'supports interleaved serialization without shared state' do
    entity = build_entity

    v1 = entity.represent(object, version: '1', serializable: true)
    v2 = entity.represent(object, version: '2', serializable: true)
    v3 = entity.represent(object, version: '3', serializable: true)
    v1_again = entity.represent(object, version: '1', serializable: true)

    expect(v1).to eq(legacy: 'legacy')
    expect(v2).to eq(current: 'current')
    expect(v3).to eq(future: 'future')
    expect(v1_again).to eq(legacy: 'legacy')
  end

  it 'allows different fields at disjoint ranges on the same output path' do
    entity = Class.new(Grape::Entity) do
      expose :legacy, as: :name, until: '2'
      expose :current, as: :name, since: '2'
    end

    expect(entity.represent(object, version: '1', serializable: true)).to eq(name: 'legacy')
    expect(entity.represent(object, version: '2', serializable: true)).to eq(name: 'current')
  end

  it 'rejects overlapping ranges on the same output path at build time' do
    expect do
      Class.new(Grape::Entity) do
        expose :legacy, as: :name, until: '2.1'
        expose :current, as: :name, since: '2'
      end
    end.to raise_error(ArgumentError, /overlapping version ranges/)
  end

  it 'rejects incomparable versions at build time' do
    expect do
      Class.new(Grape::Entity) do
        expose :legacy, as: :name, until: '2.1'
        expose :current, as: :name, since: 'v2-beta'
      end
    end.to raise_error(ArgumentError, /invalid version|incomparable versions/)
  end

  it 'rejects overlapping inherited declarations on the same output path' do
    parent_entity = Class.new(Grape::Entity) do
      expose :name
    end

    expect do
      Class.new(parent_entity) do
        expose :current, as: :name, since: '2'
      end
    end.to raise_error(ArgumentError, /overlapping version ranges/)
  end

  it 'allows disjoint inherited declarations on the same output path without override' do
    parent_entity = Class.new(Grape::Entity) do
      expose :legacy, as: :name, until: '2'
    end
    entity = Class.new(parent_entity) do
      expose :current, as: :name, since: '2'
    end

    expect(entity.represent(object, version: '1', serializable: true)).to eq(name: 'legacy')
    expect(entity.represent(object, version: '2', serializable: true)).to eq(name: 'current')
  end

  it 'treats override as replacement of the inherited output path' do
    parent_entity = Class.new(Grape::Entity) do
      expose :name
    end
    entity = Class.new(parent_entity) do
      expose :current, as: :name, since: '2', override: true
    end

    expect(entity.represent(object, version: '1', serializable: true)).to eq({})
    expect(entity.represent(object, version: '2', serializable: true)).to eq(name: 'current')
  end

  it 'applies override consistently across inherited nested paths' do
    parent_entity = Class.new(Grape::Entity) do
      expose :details do
        expose :name
      end
    end

    child_entity = Class.new(parent_entity) do
      expose :details do
        expose :name, as: :other_name, override: true
      end
    end

    expect(child_entity.represent(object, version: '2', serializable: true)).to eq(details: { other_name: 'name' })
  end

  it 'selects documentation by version without polluting other requests' do
    entity = Class.new(Grape::Entity) do
      expose :legacy, until: '2', documentation: { desc: 'legacy' }
      expose :current, since: '2', documentation: { desc: 'current' }
    end

    v1_docs = entity.documentation('1')
    v2_docs = entity.documentation(version: '2')
    legacy_docs = entity.documentation

    expect(v1_docs).to eq(legacy: { desc: 'legacy' })
    expect(v2_docs).to eq(current: { desc: 'current' })
    expect(legacy_docs).to eq(legacy: { desc: 'legacy' }, current: { desc: 'current' })
  end

  it 'selects fields once for each represented version' do
    counter = Class.new do
      attr_reader :legacy_count, :current_count

      def initialize
        @legacy_count = 0
        @current_count = 0
      end

      def legacy
        @legacy_count += 1
        'legacy'
      end

      def current
        @current_count += 1
        'current'
      end
    end.new

    entity = build_entity

    entity.represent(counter, version: '1', serializable: true)
    entity.represent(counter, version: '2', serializable: true)

    expect(counter.legacy_count).to eq(1)
    expect(counter.current_count).to eq(1)
  end
end
