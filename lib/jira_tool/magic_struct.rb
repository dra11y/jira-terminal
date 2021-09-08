require 'ostruct'

module JiraTool
  class MagicStruct < OpenStruct
    def initialize(hash = {})
      unless hash.is_a?(MagicStruct)
        hash = JSON.parse(hash) if hash.is_a?(String)
        hash = hash.transform_values do |val|
          case val
          when Array
            val.map { |v| v.is_a?(Hash) ? MagicStruct.new(v) : v }
          when Hash then MagicStruct.new(val)
          else val
          end
        end
      end
      super(hash)
    rescue StandardError
      raise Errors::ArgumentError, 'Object provided is not a Hash, OpenStruct, or valid JSON!'
    end

    def to_h
      # We can clear this cache by setting a value or calling #reload
      # OpenStruct has alias_method :set_ostruct_member_value!, :[]=,
      # so this should work with instance.x = ... as well as instance['x'] = ...
      @to_h ||= begin
        super.transform_values do |val|
          # Probably still buggy...
          if val.is_a?(Array)
            val.map { |v| v.respond_to?(:to_h) ? v.to_h : v }
          else
            val.respond_to?(:to_h) ? val.to_h : val
          end
        end
      end
    end

    def []=(name, value)
      @to_h = nil
      super
    end

    def reload
      @to_h = nil
      self
    end

    delegate :keys, :to_json, to: :to_h
    delegate :empty?, :blank?, :present?, :presence, to: :keys
  end
end
