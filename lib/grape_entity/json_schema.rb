# frozen_string_literal: true

module Grape
  class Entity
    # Exports a JSON Schema (draft 2020-12) describing the structure produced
    # by Entity.represent for a given entity class.
    #
    # Unlike Entity.documentation, which only bubbles up the per-field
    # `:documentation` hashes, this builds an actual schema of the output:
    #
    # * property names are the output aliases (`:as`) of the exposures
    # * types, `required` flags, descriptions, enums and collection
    #   (`is_array`) information are reused from the declared
    #   `:documentation` exposure options
    # * nested entities declared with `:using` are emitted once under `$defs`
    #   and referenced with `$ref`, so recursive entities terminate instead of
    #   expanding forever
    # * conditional exposures (`:if` / `:unless` / `expose_nil: false`) are
    #   never executed; the fields are marked optional and annotated with an
    #   `x-conditional` extension explaining why
    # * merged hashes, dynamic (proc) keys and custom formatters whose result
    #   type is not declared cannot be inferred statically; they are reported
    #   under `x-undetermined-fields` instead of guessing a wrong precise type
    #
    # @example
    #   schema = API::Entities::User.json_schema(collection: true)
    #   schema = API::Entities::User.json_schema(only: [:id, { status: [:id] }])
    module JsonSchema
      DIALECT = 'https://json-schema.org/draft/2020-12/schema'

      # Sentinel for "argument not passed", so `root: nil` can be told apart
      # from no `root` argument at all.
      UNDEFINED = Object.new.freeze

      CONDITIONAL_REASON =
        'presence depends on runtime options or the represented object and ' \
        'cannot be determined statically; the field is therefore optional'

      STRING_TYPE_MAP = {
        'string' => 'string',
        'symbol' => 'string',
        'text' => 'string',
        'date' => 'string',
        'datetime' => 'string',
        'time' => 'string',
        'integer' => 'integer',
        'int' => 'integer',
        'long' => 'integer',
        'number' => 'number',
        'float' => 'number',
        'double' => 'number',
        'decimal' => 'number',
        'bigdecimal' => 'number',
        'boolean' => 'boolean',
        'bool' => 'boolean',
        'object' => 'object',
        'hash' => 'object',
        'array' => 'array',
        'null' => 'null',
        'nil' => 'null'
      }.freeze

      STRING_FORMAT_MAP = {
        'date' => 'date',
        'datetime' => 'date-time',
        'date-time' => 'date-time',
        'time' => 'date-time'
      }.freeze

      class << self
        # Builds the JSON Schema for an entity class.
        #
        # @param entity_class [Class] a Grape::Entity subclass
        # @param only [Array, nil] fields to include, same shape as the
        #   runtime `:only` option (nested hashes allowed)
        # @param except [Array, nil] fields to exclude, same shape as the
        #   runtime `:except` option
        # @param collection [Boolean] whether the schema should describe a
        #   collection representation (array of objects)
        # @param root [String, Symbol, nil, false] override the root element
        #   name, mirroring the `:root` option of Entity.represent; pass nil
        #   or false to force no root even if the entity declares one
        # @return [Hash] the JSON Schema
        def export(entity_class, only: nil, except: nil, collection: false, root: UNDEFINED)
          Exporter.new(
            entity_class,
            only: only,
            except: except,
            collection: collection,
            root: root
          ).export
        end
      end

      # Walks the exposure tree of an entity class and assembles the schema.
      class Exporter
        def initialize(entity_class, only:, except:, collection:, root:)
          @entity_class = entity_class
          @collection = collection
          @root_option = root
          @export_options = Options.new(only: only, except: except)
          @defs = {}
          @building = []
          @undetermined = []
        end

        def export
          body = root_body_schema

          schema = { '$schema' => DIALECT }
          schema.merge!(body)
          schema['$defs'] = @defs unless @defs.empty?
          schema['x-undetermined-fields'] = @undetermined unless @undetermined.empty?
          schema
        end

        private

        def root_body_schema
          @building << @entity_class
          object_schema = build_object_schema(@entity_class, @export_options)
          @building.pop

          # If the root entity referenced itself recursively, a placeholder
          # def was registered; fill it with the schema just built.
          root_def = def_name(@entity_class)
          @defs[root_def] = object_schema if @defs.key?(root_def)

          body = object_schema
          body = { 'type' => 'array', 'items' => body } if collection_representation?

          root_element = effective_root_element
          return body unless root_element

          {
            'type' => 'object',
            'properties' => { root_element.to_s => body },
            'required' => [root_element.to_s]
          }
        end

        def collection_representation?
          @collection && !present_collection?
        end

        def present_collection?
          @entity_class.instance_variable_defined?(:@present_collection) &&
            @entity_class.instance_variable_get(:@present_collection) ? true : false
        end

        def effective_root_element
          if !@root_option.equal?(UNDEFINED)
            @root_option || nil
          else
            root_type = collection_representation? ? :collection_root : :root
            @entity_class.root_element(root_type)
          end
        end

        def def_name(klass)
          name = klass.name
          name.nil? || name.empty? ? "AnonymousEntity_#{klass.object_id}" : name
        end

        def build_object_schema(klass, options)
          properties = {}
          required = []
          all_of = []

          klass.root_exposures.each do |exposure|
            apply_exposure(exposure, options, properties, required, all_of)
          end

          object_schema(properties, required, all_of)
        end

        def build_nested_object_schema(nesting_exposure, options)
          properties = {}
          required = []
          all_of = []

          nesting_exposure.nested_exposures.each do |nested|
            apply_exposure(nested, options, properties, required, all_of)
          end

          object_schema(properties, required, all_of)
        end

        def object_schema(properties, required, all_of)
          schema = { 'type' => 'object', 'properties' => properties }
          schema['required'] = required unless required.empty?
          schema['allOf'] = all_of unless all_of.empty?
          schema
        end

        def apply_exposure(exposure, options, properties, required, all_of)
          if exposure.dynamic_key?
            report_undetermined(
              exposure,
              'output key is computed at runtime (proc given with :as) and cannot be determined statically'
            )
            return
          end

          return unless options.should_return_key?(exposure.key)

          if exposure.for_merge
            apply_merge_exposure(exposure, options, all_of)
            return
          end

          property = property_schema(exposure, options.for_nesting(exposure.key))
          annotate_conditional(exposure, property)
          add_property(properties, required, exposure.key.to_s, property, exposure)
        end

        def add_property(properties, required, key, property, exposure)
          if mergeable_object_schema?(properties[key]) && mergeable_object_schema?(property)
            # Subsequent nesting exposures with the same name are merged at
            # runtime; mirror that statically.
            properties[key]['properties'].merge!(property['properties'])
            merged_required = (properties[key]['required'] || []) | (property['required'] || [])
            properties[key]['required'] = merged_required unless merged_required.empty?
          else
            properties[key] = property
          end

          required << key if required_exposure?(exposure)
        end

        def mergeable_object_schema?(schema)
          schema.is_a?(Hash) && schema['type'] == 'object' && schema['properties'].is_a?(Hash)
        end

        def apply_merge_exposure(exposure, options, all_of)
          if exposure.is_a?(Exposure::RepresentExposure)
            using = resolve_using_class(exposure)
            if using
              # The represented hash is merged into the parent output, so the
              # parent object must also satisfy the merged entity's schema.
              all_of << entity_ref(using, options.for_nesting(exposure.key))
            else
              report_undetermined(
                exposure,
                "merged exposure :using #{exposure.using_class_name.inspect} does not resolve " \
                'to a Grape::Entity class; merged keys cannot be inferred'
              )
            end
          else
            report_undetermined(
              exposure,
              'merged keys are determined at runtime and cannot be inferred statically; ' \
              'declare the merged fields explicitly or avoid :merge'
            )
          end
        end

        def property_schema(exposure, options)
          case exposure
          when Exposure::NestingExposure
            build_nested_object_schema(exposure, options)
          when Exposure::RepresentExposure
            represent_schema(exposure, options)
          when Exposure::FormatterExposure, Exposure::FormatterBlockExposure
            formatter_schema(exposure)
          else
            documented_value_schema(exposure) || {}
          end
        end

        def represent_schema(exposure, options)
          using = resolve_using_class(exposure)
          unless using
            report_undetermined(
              exposure,
              "exposure :using #{exposure.using_class_name.inspect} does not resolve to a " \
              'Grape::Entity class; the nested structure cannot be inferred'
            )
            return {}
          end

          ref = entity_ref(using, options)
          if documentation_value(exposure, :is_array)
            { 'type' => 'array', 'items' => ref }
          else
            ref
          end
        end

        def formatter_schema(exposure)
          schema = documented_value_schema(exposure)
          return schema if declares_type?(exposure)

          report_undetermined(
            exposure,
            'custom formatter may change the value type and no documentation type is declared; ' \
            'add documentation: { type: ... } to describe the formatted output'
          )
          schema || {}
        end

        # Registers (if needed) the def for a nested entity and returns a
        # `$ref` to it. Recursion terminates because a class that is already
        # being built is referenced instead of expanding again.
        def entity_ref(klass, options)
          name = def_name(klass)
          return { '$ref' => "#/$defs/#{name}" } if @defs.key?(name)

          if @building.include?(klass)
            @defs[name] = nil
            return { '$ref' => "#/$defs/#{name}" }
          end

          @building << klass
          @defs[name] = nil
          @defs[name] = build_object_schema(klass, options)
          @building.delete(klass)
          { '$ref' => "#/$defs/#{name}" }
        end

        def resolve_using_class(exposure)
          klass = exposure.using_class
          klass if klass.is_a?(Class) && klass <= Grape::Entity
        rescue NameError
          nil
        end

        def documented_value_schema(exposure)
          doc = exposure.documentation
          return nil if doc.nil? || doc.empty?

          schema = {}
          type = documentation_value(exposure, :type)
          apply_declared_type(schema, exposure, type) if type
          description = documentation_value(exposure, :desc)
          schema['description'] = description if description
          values = documentation_value(exposure, :values)
          schema['enum'] = values if values.is_a?(Array)
          default = documentation_value(exposure, :default)
          schema['default'] = default unless default.nil?

          if documentation_value(exposure, :is_array)
            item_schema = schema.reject { |key, _| key == 'description' }
            array_schema = { 'type' => 'array', 'items' => item_schema }
            array_schema['description'] = schema['description'] if schema['description']
            return array_schema
          end

          schema.empty? ? nil : schema
        end

        def apply_declared_type(schema, exposure, type)
          json_type = map_type(type)
          if json_type
            schema['type'] = json_type
            format = format_for(type)
            schema['format'] = format if format
          else
            report_undetermined(
              exposure,
              "declared documentation type #{type.inspect} cannot be mapped to a JSON Schema type"
            )
          end
        end

        def map_type(type)
          case type
          when Class, Module
            map_class_type(type)
          when Array
            mapped = type.map { |t| map_type(t) }.compact.uniq
            mapped unless mapped.empty?
          else
            STRING_TYPE_MAP[type.to_s.downcase.gsub(/[\s_]+/, '')]
          end
        end

        def map_class_type(klass)
          return 'string' if klass <= String
          return 'integer' if klass <= Integer
          return 'number' if klass <= Numeric
          return 'boolean' if klass <= TrueClass || klass <= FalseClass
          return 'object' if klass <= Hash
          return 'array' if klass <= Array
          return 'string' if klass <= Symbol
          return 'string' if defined?(Date) && klass <= Date
          return 'string' if klass <= Time

          nil
        end

        def format_for(type)
          if type.is_a?(Class)
            return 'date-time' if defined?(DateTime) && type <= DateTime
            return 'date' if defined?(Date) && type <= Date
            return 'date-time' if type <= Time

            nil
          else
            STRING_FORMAT_MAP[type.to_s.downcase.gsub(/[\s_]+/, '')]
          end
        end

        def declares_type?(exposure)
          !documentation_value(exposure, :type).nil?
        end

        def documentation_value(exposure, key)
          doc = exposure.documentation
          return nil unless doc

          doc[key] || doc[key.to_s]
        end

        def required_exposure?(exposure)
          return false if exposure.conditional?

          documentation_value(exposure, :required) == true
        end

        def annotate_conditional(exposure, property)
          notes = conditional_notes(exposure)
          return if notes.empty?

          property['x-conditional'] = {
            'conditions' => notes,
            'reason' => CONDITIONAL_REASON
          }
        end

        def conditional_notes(exposure)
          conditions = exposure.conditions.dup
          notes = []

          unless exposure.expose_nil?
            # The expose_nil guard is compiled as the last condition.
            conditions.pop
            notes << 'omitted when the value is nil (expose_nil: false)'
          end

          conditions.each { |condition| notes << condition_note(condition) }
          notes
        end

        def condition_note(condition)
          keyword = condition.inversed? ? 'unless' : 'if'
          case condition
          when Condition::HashCondition
            "#{keyword}: #{condition.cond_hash.inspect} (matched against runtime options)"
          when Condition::SymbolCondition
            "#{keyword}: :#{condition.symbol} (matched against runtime options)"
          else
            "#{keyword}: proc evaluated at runtime; not executed during schema export"
          end
        end

        def report_undetermined(exposure, reason)
          entry = { 'attribute' => exposure.attribute.to_s, 'reason' => reason }
          @undetermined << entry unless @undetermined.include?(entry)
        end
      end
    end
  end
end
