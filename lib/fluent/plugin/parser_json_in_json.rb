# see:
#   https://github.com/pfremm/fluent-plugin-json-in-json/tree/0.2
require 'yajl'

module Fluent
  class TextParser
    class JSONInJSONParser < Parser
      Fluent::Plugin.register_parser('json_in_json', self)

      config_param :time_key, :string, :default => 'time'
      config_param :time_format, :string, :default => nil
      config_param :key, :string, :default => nil

      def configure(conf)
        super

        unless @time_format.nil?
          @time_parser = TimeParser.new(@time_format)
          @mutex = Mutex.new
        end
      end

      def flatten(json, prefix)
        json.keys.each do |key|
          if prefix.empty?
            full_path = key
          else
            full_path = [prefix, key].join('.')
          end

          if json[key].is_a?(Hash)
            value = json[key]
            json.delete key
            json.merge! flatten(value, full_path)
          else
            value = json[key]
            json.delete key
            json[full_path] = value
          end
        end
        return json
      end

      def parse(text)
        record = Yajl.load(text)

        value = @keep_time_key ? record[@time_key] : record.delete(@time_key)
        if value
          if @time_format
            time = @mutex.synchronize { @time_parser.parse(value) }
          else
            begin
              time = value.to_i
            rescue => e
              raise ParserError, "invalid time value: value = #{value}, error_class = #{e.class.name}, error = #{e.message}"
            end
          end
        else
          if @estimate_current_event
            time = Engine.now
          else
            time = nil
          end
        end

        values = Hash.new
        record.each do |k, v|
          if @key && k == @key
            if v[0] == '{'
              deserialized = Yajl.load(v)
              if deserialized.is_a?(Hash)
                values.merge!(flatten(deserialized, ""))
                record.delete k
              end
            end
          end
        end
        record.merge!(values)

        if block_given?
          yield time, record
        else
          return time, record
        end
      rescue Yajl::ParseError
        if block_given?
          yield nil, nil
        else
          return nil, nil
        end
      end
    end
  end
end
