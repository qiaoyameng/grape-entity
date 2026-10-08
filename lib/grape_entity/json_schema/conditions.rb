# frozen_string_literal: true

module Grape
  class Entity
    module JsonSchema
      # Static descriptions of exposure conditions for schema notes.
      module Conditions
        module_function

        # Proc/symbol outcomes depend on runtime state and are not evaluated.
        def describe_condition(condition)
          case condition
          when Grape::Entity::Condition::HashCondition
            pairs = condition.cond_hash.map { |key, value| "#{key}: #{value.inspect}" }
            "#{condition.inversed? ? 'unless' : 'if'} { #{pairs.join(', ')} }"
          when Grape::Entity::Condition::BlockCondition
            condition.inversed? ? 'unless <proc>' : 'if <proc>'
          when Grape::Entity::Condition::SymbolCondition
            "#{condition.inversed? ? 'unless' : 'if'} :#{condition.symbol}"
          end
        end
      end
    end
  end
end
