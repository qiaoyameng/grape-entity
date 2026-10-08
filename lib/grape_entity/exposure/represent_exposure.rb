# frozen_string_literal: true

module Grape
  class Entity
    module Exposure
      class RepresentExposure < Base
        attr_reader :using_class_name, :subexposure

        def setup(using_class_name, subexposure)
          @using_class = nil
          @using_class_name = using_class_name
          @subexposure = subexposure
        end

        def dup_args
          [*super, using_class_name, subexposure]
        end

        def ==(other)
          super &&
            @using_class_name == other.using_class_name &&
            @subexposure == other.subexposure
        end

        def value(entity, options)
          new_options = options.for_nesting(key(entity))
          new_options = apply_version_mapping(new_options, options[:version])
          using_class.represent(@subexposure.value(entity, options), new_options)
        end

        def valid?(entity, _options = nil)
          @subexposure.valid?(entity)
        end

        def using_class
          @using_class ||= if @using_class_name.respond_to? :constantize
                             @using_class_name.constantize
                           else
                             @using_class_name
                           end
        end

        private

        def using_options_for(options)
          options.for_nesting(key)
        end

        def apply_version_mapping(options, current_version)
          mapping = self.options[:version_mapping] || self.options[:version]
          return options if mapping.nil?

          mapped_version =
            case mapping
            when Proc
              mapping.arity.zero? ? mapping.call : mapping.call(current_version)
            when Hash
              map_version(mapping, current_version)
            else
              mapping
            end

          options.merge(version: mapped_version)
        end

        def map_version(mapping, current_version)
          return current_version if current_version.nil?

          target = Version.cast(current_version)
          mapped = mapping.find { |version, _| Version.cast(version) == target }
          mapped ? mapped.last : current_version
        end
      end
    end
  end
end
