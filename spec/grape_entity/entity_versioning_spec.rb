# frozen_string_literal: true

describe Grape::Entity do
  # A model that counts how often each attribute is read, so tests can
  # prove that version-excluded fields never execute business code.
  class VersionedCountingModel
    attr_reader :fetch_counts

    def initialize(values)
      @values = values
      @fetch_counts = Hash.new(0)
      values.each_key do |name|
        define_singleton_method(name) { read(name) }
      end
    end

    def read(name)
      @fetch_counts[name] += 1
      @values[name]
    end
  end

  let(:fresh_class) { Class.new(Grape::Entity) }
  let(:model) do
    VersionedCountingModel.new(
      id: 1,
      legacy_name: 'old name',
      name: 'new name',
      secret: 'hidden',
      child: child_model
    )
  end
  let(:child_model) { VersionedCountingModel.new(old_fact: 'o', new_fact: 'n') }

  def represent(klass, version)
    klass.represent(model, version: version, serializable: true)
  end

  describe 'version-ranged exposures' do
    subject(:entity_class) do
      Class.new(Grape::Entity) do
        expose :id
        expose :legacy_name, as: :name, until: '2.0'
        expose :name, since: '2.0'
      end
    end

    it 'serves v1 and v2 clients from the same entity' do
      expect(represent(entity_class, '1.0')).to eq(id: 1, name: 'old name')
      expect(represent(entity_class, '2.0')).to eq(id: 1, name: 'new name')
    end

    it 'treats the :until boundary as exclusive' do
      expect(represent(entity_class, '1.99')[:name]).to eq 'old name'
      expect(represent(entity_class, '2.0')[:name]).to eq 'new name'
    end

    it 'compares versions numerically, so 2.10 is not less than 2.9' do
      klass = Class.new(Grape::Entity) do
        expose :legacy_name, as: :name, until: '2.10'
        expose :name, since: '2.10'
      end
      expect(represent(klass, '2.9')).to eq(name: 'old name')
      expect(represent(klass, '2.10')).to eq(name: 'new name')
    end

    it 'does not filter anything when no target version is given' do
      expect(entity_class.represent(model, serializable: true)).to eq(id: 1, name: 'new name')
    end

    it 'rejects a target version that cannot be compared' do
      expect { represent(entity_class, 'latest') }.to raise_error(ArgumentError, /not a comparable version/)
    end
  end

  describe 'filtering happens before any business code' do
    it 'does not call the attribute getter of version-excluded fields' do
      fresh_class.expose :legacy_name, until: '2.0'
      fresh_class.expose :name, since: '2.0'

      represent(fresh_class, '1.0')
      expect(model.fetch_counts[:name]).to eq 0
      expect(model.fetch_counts[:legacy_name]).to eq 1
    end

    it 'does not evaluate conditions of version-excluded fields' do
      evaluated = []
      fresh_class.expose :secret, until: '2.0', if: ->(_object, _options) { (evaluated << :secret) && true }

      represent(fresh_class, '2.0')
      expect(evaluated).to be_empty
      expect(model.fetch_counts[:secret]).to eq 0
    end

    it 'does not fetch values just to evaluate a condition' do
      fresh_class.expose :secret, until: '2.0', if: ->(object, _options) { object.secret == 'hidden' }

      represent(fresh_class, '2.0')
      expect(model.fetch_counts[:secret]).to eq 0
    end

    it 'does not run formatters of version-excluded fields' do
      formatted = []
      fresh_class.format_with(:tracked) { |value| (formatted << value) && value }
      fresh_class.expose :legacy_name, until: '2.0', format_with: :tracked

      represent(fresh_class, '2.0')
      expect(formatted).to be_empty
      expect(model.fetch_counts[:legacy_name]).to eq 0
    end

    it 'does not run exposure blocks of version-excluded fields' do
      ran = []
      fresh_class.expose :computed, until: '2.0' do |object, _options|
        ran << :computed
        object.legacy_name
      end

      represent(fresh_class, '2.0')
      expect(ran).to be_empty
    end
  end

  describe 'interleaved serialization of two versions' do
    subject(:entity_class) do
      child_class = Class.new(Grape::Entity) do
        expose :old_fact, until: '2.0'
        expose :new_fact, since: '2.0'
      end

      Class.new(Grape::Entity) do
        expose :id
        expose :legacy_name, as: :name, until: '2.0'
        expose :name, since: '2.0'
        expose :child, using: child_class
      end
    end

    it 'produces stable per-version output and exact fetch counts' do
      outputs = %w[1.0 2.0 1.0 2.0].map { |version| represent(entity_class, version) }

      expect(outputs[0]).to eq(id: 1, name: 'old name', child: { old_fact: 'o' })
      expect(outputs[1]).to eq(id: 1, name: 'new name', child: { new_fact: 'n' })
      expect(outputs[2]).to eq(outputs[0])
      expect(outputs[3]).to eq(outputs[1])

      expect(model.fetch_counts[:id]).to eq 4
      expect(model.fetch_counts[:legacy_name]).to eq 2
      expect(model.fetch_counts[:name]).to eq 2
      expect(child_model.fetch_counts[:old_fact]).to eq 2
      expect(child_model.fetch_counts[:new_fact]).to eq 2
    end

    it 'applies the boundary version consistently to parent and child entities' do
      at_boundary = represent(entity_class, '2.0')
      expect(at_boundary).to eq(id: 1, name: 'new name', child: { new_fact: 'n' })

      just_before = represent(entity_class, '1.9')
      expect(just_before).to eq(id: 1, name: 'old name', child: { old_fact: 'o' })
    end
  end

  describe 'build-time validation' do
    it 'allows the same output path in non-overlapping ranges after inheritance' do
      parent = Class.new(Grape::Entity) do
        expose :legacy_name, as: :name, until: '2.0'
      end
      child = Class.new(parent) do
        expose :name, since: '2.0'
      end

      expect(represent(child, '1.5')).to eq(name: 'old name')
      expect(represent(child, '2.5')).to eq(name: 'new name')
    end

    it 'rejects overlapping ranges for the same output path at build time' do
      fresh_class.expose :legacy_name, as: :name, until: '2.0'

      expect { fresh_class.expose :name, since: '1.5' }
        .to raise_error(ArgumentError, /overlapping version range/)
    end

    it 'rejects overlapping ranges declared in a subclass at build time' do
      parent = Class.new(Grape::Entity) do
        expose :legacy_name, as: :name, until: '2.0'
      end

      expect { Class.new(parent) { expose :name, since: '1.0' } }
        .to raise_error(ArgumentError, /overlapping version range/)
    end

    it 'rejects identical ranges for the same output path' do
      fresh_class.expose :legacy_name, as: :name, since: '1.0', until: '2.0'

      expect { fresh_class.expose :name, since: '1.0', until: '2.0' }
        .to raise_error(ArgumentError, /overlapping version range/)
    end

    it 'rejects versions that cannot be compared at build time' do
      expect { fresh_class.expose :name, since: 'not-a-version' }
        .to raise_error(ArgumentError, /not a comparable version/)
      expect { fresh_class.expose :name, until: '2..1' }
        .to raise_error(ArgumentError, /not a comparable version/)
    end

    it 'keeps :override semantics: it replaces same-attribute declarations before the check' do
      parent = Class.new(Grape::Entity) do
        expose :legacy_name, as: :name, until: '2.0'
      end
      child = Class.new(parent) do
        expose :legacy_name, as: :name, override: true, since: '1.0', until: '2.0'
      end

      expect(child.root_exposures.size).to eq 1
      expect(represent(child, '1.5')).to eq(name: 'old name')
      expect(represent(child, '2.0')).to eq({})
    end

    it 'still allows re-exposing without version constraints (legacy last-wins)' do
      fresh_class.expose :legacy_name, as: :name
      fresh_class.expose :name, since: '2.0'

      expect(represent(fresh_class, '1.0')).to eq(name: 'old name')
      expect(represent(fresh_class, '2.0')).to eq(name: 'new name')
    end

    it 'switches nesting blocks sharing an output path by version' do
      entity_class = Class.new(Grape::Entity) do
        expose :child, until: '2.0' do
          expose :legacy_name, as: :name
        end
        expose :child, since: '2.0' do
          expose :name
        end
      end

      expect(represent(entity_class, '1.0')).to eq(child: { name: 'old name' })
      expect(represent(entity_class, '2.0')).to eq(child: { name: 'new name' })
    end

    it 'rejects overlapping nesting blocks sharing an output path' do
      expect do
        Class.new(Grape::Entity) do
          expose(:child, until: '2.0') { expose :legacy_name }
          expose(:child, since: '1.5') { expose :name }
        end
      end.to raise_error(ArgumentError, /overlapping version range/)
    end
  end

  describe 'nested entities' do
    let(:child_class) do
      Class.new(Grape::Entity) do
        expose :old_fact, until: '2.0'
        expose :new_fact, since: '2.0'
      end
    end

    it 'inherits the target version into nested entities' do
      fresh_class.expose :child, using: child_class

      expect(represent(fresh_class, '1.0')[:child]).to eq(old_fact: 'o')
      expect(represent(fresh_class, '2.0')[:child]).to eq(new_fact: 'n')
    end

    it 'allows pinning a nested entity to an explicit version' do
      fresh_class.expose :child, using: child_class, version: '1.0'

      expect(represent(fresh_class, '2.0')[:child]).to eq(old_fact: 'o')
      expect(child_model.fetch_counts[:new_fact]).to eq 0
    end

    it 'allows mapping the inherited version to a nested version' do
      fresh_class.expose :child, using: child_class, version: { '2.0' => '1.5' }

      expect(represent(fresh_class, '2.0')[:child]).to eq(old_fact: 'o')
      expect(represent(fresh_class, '1.0')[:child]).to eq(old_fact: 'o')
    end
  end

  describe '.documentation' do
    subject(:doc_class) do
      Class.new(Grape::Entity) do
        expose :legacy_name, documentation: { type: 'string', desc: 'v1 name' }, until: '2.0'
        expose :name, documentation: { type: 'string', desc: 'v2 name' }, since: '2.0'
        expose :id, documentation: { type: 'integer' }
      end
    end

    it 'selects documented fields by the same version rules' do
      expect(doc_class.documentation('1.0')).to eq(
        legacy_name: { type: 'string', desc: 'v1 name' },
        id: { type: 'integer' }
      )
      expect(doc_class.documentation('2.0')).to eq(
        name: { type: 'string', desc: 'v2 name' },
        id: { type: 'integer' }
      )
    end

    it 'keeps unversioned documentation complete' do
      expect(doc_class.documentation).to eq(
        legacy_name: { type: 'string', desc: 'v1 name' },
        name: { type: 'string', desc: 'v2 name' },
        id: { type: 'integer' }
      )
    end

    it 'caches per version without polluting other versions' do
      v1 = doc_class.documentation('1.0')
      v2 = doc_class.documentation('2.0')

      expect(doc_class.documentation('1.0')).to equal v1
      expect(doc_class.documentation(Gem::Version.new('2.0'))).to equal v2
      expect(doc_class.documentation('1.0')).to eq v1
    end

    it 'uses the entity version for instance documentation queries' do
      entity = doc_class.new(model, version: '2.0')
      expect(entity.documentation).to eq(
        name: { type: 'string', desc: 'v2 name' },
        id: { type: 'integer' }
      )
    end

    it 'resets the per-version cache when exposing additional attributes' do
      doc_class.documentation('1.0')
      doc_class.expose :extra, documentation: { type: 'string' }, until: '2.0'

      expect(doc_class.documentation('1.0')).to have_key(:extra)
      expect(doc_class.documentation('2.0')).not_to have_key(:extra)
    end
  end
end
