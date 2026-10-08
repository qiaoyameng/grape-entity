# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Root wrapper and collection rendering decisions.
      module Roots
        private

        def present_collection?
          return @present_collection_option unless @present_collection_option.nil?

          @entity.instance_variable_get(:@present_collection) == true
        end

        def root_name(kind)
          @entity.root_element(kind)
        end

        def wrap_root(inner)
          if @collection
            return inner if present_collection?

            wrap_with_root(inner, root_name(:collection_root))
          else
            wrap_with_root(inner, root_name(:root))
          end
        end

        def wrap_with_root(inner, declared_root)
          case @root_option
          when :auto
            declared_root ? root_object(declared_root, inner) : inner
          when false, nil
            inner
          else
            root_object(@root_option.to_s, inner)
          end
        end

        def root_object(root, inner)
          {
            'type' => 'object',
            'properties' => { root => inner },
            'required' => [root],
            'additionalProperties' => false
          }
        end
      end
    end
  end
end
