# frozen_string_literal: true

require 'rubygems/version'

module Grape
  class Entity
    # A comparable range of versions declared through the :since and :until
    # exposure options. Versions are compared with Gem::Version semantics, so
    # 2.10 sorts after 2.9 and boundaries are never compared as plain strings.
    # The :since boundary is inclusive, the :until boundary is exclusive.
    class VersionRange
      attr_reader :since, :until

      # Builds a VersionRange from exposure options, or returns nil when no
      # version constraint was declared. Raises ArgumentError when a boundary
      # cannot be coerced into a comparable version.
      def self.build(options)
        since = options[:since]
        until_ = options[:until]
        return if since.nil? && until_.nil?

        new(since, until_)
      end

      # Coerces the given value into a comparable Gem::Version.
      # Raises ArgumentError for values that cannot be compared.
      def self.coerce(version, label = 'version')
        return if version.nil?
        return version if version.is_a?(Gem::Version)

        Gem::Version.new(version.to_s)
      rescue ArgumentError
        raise ArgumentError, "#{label} #{version.inspect} is not a comparable version"
      end

      def initialize(since, until_)
        @since = self.class.coerce(since, ':since')
        @until = self.class.coerce(until_, ':until')

        return unless @since && @until && @since >= @until

        raise ArgumentError,
              ":since (#{since.inspect}) must be lower than :until (#{until_.inspect})"
      end

      # Whether the given target version falls inside the range.
      # A nil target version disables filtering entirely.
      def include?(version)
        return true if version.nil?

        comparable = self.class.coerce(version)
        (@since.nil? || comparable >= @since) && (@until.nil? || comparable < @until)
      end

      # Whether two half-open ranges share at least one version.
      def overlaps?(other)
        !bounded_before?(@until, other.since) && !bounded_before?(other.until, @since)
      end

      def ==(other)
        other.is_a?(VersionRange) && since == other.since && self.until == other.until
      end

      private

      # upper <= lower, treating nil bounds as unbounded
      def bounded_before?(upper, lower)
        !upper.nil? && !lower.nil? && upper <= lower
      end
    end
  end
end
