# frozen_string_literal: true

module Escalated
  module Support
    # SQL that reads one value out of a JSON column, written for the database
    # the connection is on. SQLite, PostgreSQL and MySQL share no JSON function:
    # JSON_UNQUOTE(JSON_EXTRACT()) exists only on MySQL, json_extract() only on
    # SQLite, and PostgreSQL has operators instead (and no LIKE for json).
    #
    # A path is a dotted list of plain names ("plan", "owner.team"). It ends up
    # inside the SQL text, so anything else is refused rather than quoted.
    module JsonQuery
      PATH = /\A[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\z/
      COMPARISONS = ['=', '!=', '<', '>', '<=', '>=', 'IN', 'NOT IN'].freeze

      module_function

      def valid_path?(path)
        PATH.match?(path.to_s)
      end

      # [sql, bind] comparing the value at +path+ with +value+, so that a number
      # is compared as a number and anything else (strings, and booleans as
      # "true"/"false") as the value's text. A nil value asks whether the path
      # holds nothing. IN and NOT IN take an array.
      def condition(connection, column, path, operator, value)
        return [null_check(connection, column, path, operator)] if value.nil? && %w[= !=].include?(operator)

        values = Array(value)
        if COMPARISONS.include?(operator) && values.any? && values.all?(Numeric)
          return [placeholder(number(connection, column, path), operator), value]
        end

        bind = value.is_a?(Array) ? value.map(&:to_s) : value.to_s
        [placeholder(text(connection, column, path), operator), bind]
      end

      def null_check(connection, column, path, operator)
        "#{text(connection, column, path)} IS #{operator == '!=' ? 'NOT NULL' : 'NULL'}"
      end

      # The value as text: strings unquoted, numbers and booleans as written.
      def text(connection, column, path)
        col = connection.quote_column_name(column)

        case adapter(connection)
        when :postgresql then "((#{col})::jsonb #>> '#{pg_path(path)}')"
        when :mysql then "JSON_UNQUOTE(JSON_EXTRACT(#{col}, '#{json_path(path)}'))"
        else
          "(CASE json_type(#{col}, '#{json_path(path)}') WHEN 'true' THEN 'true' WHEN 'false' THEN 'false' " \
          "ELSE CAST(json_extract(#{col}, '#{json_path(path)}') AS TEXT) END)"
        end
      end

      # The value as a number, or NULL when it is not one.
      def number(connection, column, path)
        col = connection.quote_column_name(column)

        case adapter(connection)
        when :postgresql
          "(CASE WHEN jsonb_typeof((#{col})::jsonb #> '#{pg_path(path)}') = 'number' " \
          "THEN ((#{col})::jsonb #>> '#{pg_path(path)}')::numeric END)"
        when :mysql
          "(CASE WHEN JSON_TYPE(JSON_EXTRACT(#{col}, '#{json_path(path)}')) " \
          "IN ('INTEGER', 'UNSIGNED INTEGER', 'DOUBLE', 'DECIMAL') " \
          "THEN CAST(JSON_EXTRACT(#{col}, '#{json_path(path)}') AS DECIMAL(65, 30)) END)"
        else
          "(CASE WHEN json_type(#{col}, '#{json_path(path)}') IN ('integer', 'real') " \
          "THEN json_extract(#{col}, '#{json_path(path)}') END)"
        end
      end

      # An expression to ORDER BY: each database's own JSON ordering, which puts
      # numbers in numeric order.
      def sortable(connection, column, path)
        col = connection.quote_column_name(column)

        case adapter(connection)
        when :postgresql then "((#{col})::jsonb #> '#{pg_path(path)}')"
        when :mysql then "JSON_EXTRACT(#{col}, '#{json_path(path)}')"
        else "json_extract(#{col}, '#{json_path(path)}')"
        end
      end

      def placeholder(expression, operator)
        operator.include?('IN') ? "#{expression} #{operator} (?)" : "#{expression} #{operator} ?"
      end

      def segments(path)
        raise ArgumentError, "Not a JSON path: #{path.inspect}" unless valid_path?(path)

        path.to_s.split('.')
      end

      def json_path(path)
        "$.#{segments(path).map { |segment| %("#{segment}") }.join('.')}"
      end

      def pg_path(path)
        "{#{segments(path).join(',')}}"
      end

      def adapter(connection)
        name = connection.adapter_name.downcase
        return :postgresql if name.include?('postg')
        return :mysql if name.include?('mysql') || name.include?('trilogy')

        :sqlite
      end
    end
  end
end
