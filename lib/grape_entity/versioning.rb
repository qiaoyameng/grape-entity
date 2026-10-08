# frozen_string_literal: true

module Grape
  class Entity
    class Version
      include Comparable

      attr_reader :segments

      def self.cast(value)
        return value if value.is_a?(self)

        new(value)
      end

      def initialize(value)
        @segments = parse(value)
      end

      def <=>(other)
        segments <=> self.class.cast(other).segments
      rescue ArgumentError
        nil
      end

      def to_s
        segments.join('.')
      end

      def inspect
        "#<#{self.class.name} #{self}>"
      end

      private

      def parse(value)
        case value
        when self.class
          value.segments
        when Integer, String, Symbol
          parse_string(value.to_s)
        else
          raise ArgumentError, "invalid version: #{value.inspect}"
        end
      end

      def parse_string(value)
        match = value.match(/\Av?(\d+(?:\.\d+)*)\z/)
        raise ArgumentError, "invalid version: #{value.inspect}" unless match

        match[1].split('.').map(&:to_i).reverse.drop_while(&:zero?).reverse
      end
    end

    class VersionRange
      attr_reader :since, :until_version

      def self.empty
        allocate.tap do |range|
          range.instance_variable_set(:@since, Version.new(0))
          range.instance_variable_set(:@until_version, Version.new(0))
        end
      end

      def self.cast_bound(value)
        value.nil? ? nil : Version.cast(value)
      end

      def initialize(since: nil, until_version: nil)
        @since = self.class.cast_bound(since)
        @until_version = self.class.cast_bound(until_version)

        validate!
      end

      def versioned?
        !since.nil? || !until_version.nil?
      end

      def covers?(version)
        return !versioned? if version.nil?

        target = Version.cast(version)
        (!since || target >= since) && (!until_version || target < until_version)
      end

      def overlap?(other)
        return false unless versioned? || other.versioned?
        return true unless versioned? && other.versioned?
        return false if disjoint_from?(other)

        true
      end

      def intersection(other)
        return self unless other.versioned?
        return other unless versioned?

        new_since = [since, other.since].compact.max
        new_until = [until_version, other.until_version].compact.min

        return if new_since && new_until && new_since >= new_until

        VersionRange.new(since: new_since, until_version: new_until)
      end

      def to_s
        "[#{since || '-∞'}, #{until_version || '∞'})"
      end

      private

      def validate!
        return unless since && until_version
        raise ArgumentError, "invalid version range: #{self}" unless since < until_version
      end

      def disjoint_from?(other)
        bounds = [since, until_version, other.since, other.until_version].compact
        bounds.combination(2).each do |left, right|
          raise ArgumentError, "incomparable versions: #{left.inspect} and #{right.inspect}" if (left <=> right).nil?
        end

        (since && other.until_version && since >= other.until_version) ||
          (other.since && until_version && other.since >= until_version)
      end
    end
  end
end
