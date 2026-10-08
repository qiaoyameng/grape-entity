# frozen_string_literal: true

describe Grape::Entity::VersionRange do
  describe '.build' do
    it 'returns nil when no boundaries are declared' do
      expect(described_class.build({})).to be_nil
    end

    it 'builds a range from :since and :until options' do
      range = described_class.build(since: '1.0', until: '2.0')
      expect(range.since).to eq Gem::Version.new('1.0')
      expect(range.until).to eq Gem::Version.new('2.0')
    end

    it 'rejects boundaries that cannot be compared' do
      expect { described_class.build(since: 'abc') }
        .to raise_error(ArgumentError, /not a comparable version/)
      expect { described_class.build(until: '2..1') }
        .to raise_error(ArgumentError, /not a comparable version/)
    end

    it 'rejects an empty range' do
      expect { described_class.build(since: '2.0', until: '2.0') }
        .to raise_error(ArgumentError, /must be lower/)
      expect { described_class.build(since: '2.10', until: '2.9') }
        .to raise_error(ArgumentError, /must be lower/)
    end
  end

  describe '#include?' do
    subject(:range) { described_class.build(since: '2.0', until: '2.10') }

    it 'includes the :since boundary' do
      expect(range.include?('2.0')).to be true
    end

    it 'excludes the :until boundary' do
      expect(range.include?('2.10')).to be false
    end

    it 'compares versions numerically, not as strings' do
      expect(range.include?('2.9')).to be true
      expect(described_class.build(until: '2.10').include?('2.9')).to be true
      expect(described_class.build(since: '2.9').include?('2.10')).to be true
    end

    it 'accepts Gem::Version instances' do
      expect(range.include?(Gem::Version.new('2.5'))).to be true
    end

    it 'treats a nil target version as unfiltered' do
      expect(range.include?(nil)).to be true
    end

    it 'raises for a target version that cannot be compared' do
      expect { range.include?('nope') }.to raise_error(ArgumentError, /not a comparable version/)
    end

    it 'supports open-ended ranges' do
      expect(described_class.build(since: '2.0').include?('99.0')).to be true
      expect(described_class.build(since: '2.0').include?('1.9')).to be false
      expect(described_class.build(until: '2.0').include?('0.1')).to be true
      expect(described_class.build(until: '2.0').include?('2.0')).to be false
    end
  end

  describe '#overlaps?' do
    def range(options)
      described_class.build(options)
    end

    it 'detects overlapping ranges' do
      expect(range(since: '1.0', until: '2.5').overlaps?(range(since: '2.0', until: '3.0'))).to be true
      expect(range(since: '2.0').overlaps?(range(until: '3.0'))).to be true
      expect(range(since: '1.0').overlaps?(range(since: '2.0'))).to be true
      expect(range(until: '2.0').overlaps?(range(until: '3.0'))).to be true
    end

    it 'treats adjacent ranges as non-overlapping because :until is exclusive' do
      expect(range(until: '2.0').overlaps?(range(since: '2.0'))).to be false
      expect(range(since: '1.0', until: '2.0').overlaps?(range(since: '2.0', until: '3.0'))).to be false
    end
  end
end
