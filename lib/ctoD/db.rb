require 'csv'
require 'uri'
require 'active_record'

module CtoD
  class DB
    include ActiveSupport::Inflector
    AR = ActiveRecord::Base
    attr_accessor :string_size
    attr_reader :table_name, :class_name, :uri
    def initialize(csv, uri, string_size:100)
      @table_name = File.basename(csv, '.csv').intern
      @class_name = singularize(@table_name).capitalize
      @csv = CSV.table(csv, header_converters:->h{h.strip})
      @string_size = string_size
      @table_columns = nil
      @uri = DB.connect(uri)
    end

    def table_exists?
      AR.connection.table_exists?(@table_name)
    rescue => e
      puts e
    end

    def create_table
      conn = AR.connection
      conn.create_table(@table_name) do |t|
        table_columns.each do |name, type|
          t.column name, type
        end
        t.timestamps
      end
    end

    def table_columns
      @table_columns ||= self.class.build_columns(@csv, string_size:@string_size)
    end

    def export
      self.class.const_set(@class_name, Class.new(AR))
      self.class.const_get(@class_name).create! @csv.map(&:to_hash)
    rescue => e
      puts "Something go wrong at export: #{e}"
    end

    def self.connect(uri)
      uri = URI.parse(uri)
      uri.scheme = 'postgresql' if uri.scheme=='postgres'
      settings = {
        adapter: uri.scheme,
        host: uri.host,
        username: uri.user,
        password: uri.password,
        database: uri.path[1..-1],
        encoding: 'utf8'
      }
      AR.establish_connection(settings)
      uri
    rescue => e
      puts "Something go wrong at connect: #{e}"
    end

    def self.build_columns(csv, string_size:100)
      is_date = /^\s*\d{1,4}(\-|\/)\d{1,2}(\-|\/)\d{1,2}\s*$/
      csv.first.to_hash.inject({}) do |mem, (k, v)|
        mem[k.intern] = begin
          case v
          when 'true', 'false'
            :boolean
          when is_date
            :date
          when String, Symbol
            csv[k].compact.max_by(&:size).size > string_size ? :text : :string
          when Fixnum, Float
            csv[k].any? { |e| e.is_a? Float } ? :float : :integer
          when NilClass
            :string
          else
            v.class.name.downcase.intern
          end
        end
        mem
      end
    end
  end
end
