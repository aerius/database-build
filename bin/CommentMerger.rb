##
# Utility class for fetching the database structure from the server, and storing it in the comments data structure.
# Then, merge it with the actual parsed comments.
#
class CommentMerger

  # 'comments' is a previously parsed comments. Returns a duplicate with the database structure merged into it.
  def self.merge_with_database_structure(logger, comments)
    merged_comments = deep_dup(comments)

    struct_comments = fetch_database_structure(logger)
    struct_comments.each{ |object, struct_comment_items|
      merged_comments[object] = {} unless merged_comments.has_key?(object)
      struct_comment_items.each{ |key, struct_comment_item|

        merged_comment_item = nil
        if merged_comments[object].has_key?(key) then
          merged_comment_item = merged_comments[object][key]
        elsif object == 'FUNCTION' || object == 'AGGREGATE' then
          # try again without parameter definition (only accept when there is only 1 match)
          function_without_args = key.match(/^([^\(]+)/)[1].strip
          matched_comment_item_keys = merged_comments[object].keys.select{ |functiondef| function_without_args == functiondef.match(/^([^\(]+)/)[1].strip[0..62] }
          merged_comment_item = merged_comments[object][matched_comment_item_keys[0]] if matched_comment_item_keys.length == 1
        else
          matched_comment_item_keys = merged_comments[object].keys.select{ |objectdef| key == objectdef[0..62] }
          merged_comment_item = merged_comments[object][matched_comment_item_keys[0]] if matched_comment_item_keys.length == 1
        end

        if merged_comment_item.nil? then
          merged_comments[object][key] = struct_comment_item
        else
          if merged_comment_item.columns.nil? || merged_comment_item.columns.empty? then
            merged_comment_item.columns = struct_comment_item.columns
          else
            new_columns = struct_comment_item.columns.dup
            new_columns.each_index{ |idx|
              newcolumnname = new_columns[idx][0]
              merged_comment_item.columns.each{ |columnname, _, columncomment|
                if columnname == newcolumnname then
                  new_columns[idx][2] = columncomment
                  break
                end
              }
            }
            merged_comment_item.columns = new_columns
          end

          if merged_comment_item.params.nil? || merged_comment_item.params.empty? then
            merged_comment_item.params = struct_comment_item.params
          else
            new_params = struct_comment_item.params.dup
            new_params.each_index{ |idx|
              newparamname = new_params[idx][0]
              merged_comment_item.params.each{ |paramname, _, paramcomment|
                if paramname == newparamname then
                  new_params[idx][2] = paramcomment
                  break
                end
              }
            }
            merged_comment_item.params = new_params
          end

          if merged_comment_item.returns.nil? then
            merged_comment_item.returns = struct_comment_item.returns
          else
            merged_comment_item.returns[0] = struct_comment_item.returns[0]
          end
        end
      }
    }

    return merged_comments
  end

 private

  def self.fetch_database_structure(logger)
    comments = {}

    sql_noncatalog_objects = "(SELECT array_agg(objid) || array_agg(DISTINCT pg_namespace.oid) FROM pg_depend INNER JOIN pg_namespace ON (refobjid = pg_namespace.oid) WHERE pg_namespace.oid <> pg_my_temp_schema() AND NOT nspname IN ('information_schema', 'pg_catalog', 'pg_toast'))"
    sql_extension_objects = "(SELECT array_agg(objid) || array_agg(DISTINCT pg_extension.oid) FROM pg_depend INNER JOIN pg_extension ON (refobjid = pg_extension.oid))"

    sql = <<-SQL
      SELECT
        nspname::text AS schema

        FROM pg_namespace

        WHERE
          pg_namespace.oid IN (SELECT unnest(#{sql_noncatalog_objects})) AND
          NOT pg_namespace.oid IN (SELECT unnest(#{sql_extension_objects}))
    SQL
    PostgresTools.fetch_sql_command(sql, '', logger).each{ |record|
      object = 'SCHEMA'
      comment_item = create_empty_comment_item()
      comment_item.identifier_noschema = record['schema']
      comment_item.schema = record['schema']
      comment_item.schema = '' if comment_item.schema == 'public'
      comments[object] = {} unless comments.has_key?(object)
      comments[object][(comment_item.identifier + comment_item.arguments_nodefault).downcase] = comment_item
    }

    sql = <<-SQL
      SELECT
        relkind,
        pg_class.oid::regclass::text AS identifier,
        relname::text AS identifier_noschema,
        nspname::text AS schema,
        array_to_string(array_agg(CONCAT(attname, '#', format_type(atttypid, NULL)) ORDER BY attnum), ',') AS columns

        FROM pg_class
          INNER JOIN pg_namespace ON (relnamespace = pg_namespace.oid)
          INNER JOIN pg_attribute ON (pg_class.oid = attrelid)

        WHERE
          relkind IN ('r', 'v', 'm') AND
          attnum > 0 AND NOT attisdropped AND relpersistence <> 't' AND
          pg_class.oid IN (SELECT unnest(#{sql_noncatalog_objects})) AND
          NOT pg_class.oid IN (SELECT unnest(#{sql_extension_objects}))

        GROUP BY relkind, pg_class.oid, relname, nspname
    SQL
    PostgresTools.fetch_sql_command(sql, '', logger).each{ |record|
      object = case record['relkind']
        when 'r' then 'TABLE'
        when 'v' then 'VIEW'
        when 'm' then 'MATERIALIZED VIEW'
        else next
      end
      comment_item = create_empty_comment_item()
      comment_item.identifier_noschema = record['identifier_noschema']
      comment_item.schema = record['schema']
      comment_item.schema = '' if comment_item.schema == 'public'
      record['columns'].split(',').each { |column|
        name_and_type = column.split('#')
        comment_item.columns << [name_and_type[0], name_and_type[1], '']
      }
      comments[object] = {} unless comments.has_key?(object)
      comments[object][(comment_item.identifier + comment_item.arguments_nodefault).downcase] = comment_item
    }

    sql = <<-SQL
      SELECT
        (CASE WHEN proisagg THEN 'a' ELSE 'f' END) AS prokind,
        pg_proc.oid::regproc::text AS identifier,
        proname::text AS identifier_noschema,
        nspname::text AS schema,
        CONCAT('(', replace(pg_get_function_arguments(pg_proc.oid), ' DEFAULT ', ' = '), ')') AS arguments,
        CONCAT('(', pg_get_function_identity_arguments(pg_proc.oid), ')') AS arguments_nodefault,
        pg_get_function_result(pg_proc.oid) AS returns,
        array_to_string(proargnames, ',') AS paramnames,
        array_to_string(proargmodes, ',') AS parammodes,
        (SELECT array_to_string(array_agg(format_type(typ, NULL)), ',') FROM unnest(COALESCE(proallargtypes, proargtypes)) AS typ) AS paramtypes

      FROM pg_proc
        INNER JOIN pg_namespace ON (pronamespace = pg_namespace.oid)

      WHERE
        pg_proc.oid IN (SELECT unnest(#{sql_noncatalog_objects})) AND
        NOT pg_proc.oid IN (SELECT unnest(#{sql_extension_objects}))
    SQL
    PostgresTools.fetch_sql_command(sql, '', logger).each{ |record|
      object = case record['prokind']
        when 'f' then 'FUNCTION'
        when 'a' then 'AGGREGATE'
        else next
      end
      comment_item = create_empty_comment_item()
      comment_item.identifier_noschema = record['identifier_noschema']
      comment_item.schema = record['schema']
      comment_item.schema = '' if comment_item.schema == 'public'
      comment_item.arguments = record['arguments']
      comment_item.arguments_nodefault = record['arguments_nodefault']
      comment_item.returns = [record['returns'], '']
      paramtypes = record['paramtypes'].nil? ? [] : record['paramtypes'].split(',')
      parammodes = record['parammodes'].nil? ? [] : record['parammodes'].split(',')
      paramnames = record['paramnames'].nil? ? [] : record['paramnames'].split(',')
      if !paramtypes.empty? then
        paramnames = [''] * paramtypes.size if paramnames.empty?  # may be empty if no names given
        paramnames.each_index {|idx|  # fill in any missing names
          paramnames[idx] = '$' + (idx + 1).to_s if paramnames[idx].empty?
        }
        (parammodes.size - 1).downto(0) { |idx|  # may be empty if everything is 'i'
          if parammodes[idx] == 'o' || parammodes[idx] == 't' then
            paramtypes.delete_at(idx)
            paramnames.delete_at(idx)
          end
        }
        paramtypes.each_index { |idx|
          comment_item.params << [paramnames[idx], paramtypes[idx], '']
        }
      end
      comments[object] = {} unless comments.has_key?(object)
      comments[object][(comment_item.identifier + comment_item.arguments_nodefault).downcase] = comment_item
    }

    sql = <<-SQL
      SELECT
        typtype,
        pg_type.oid::regtype::text AS identifier,
        typname::text AS identifier_noschema,
        nspname::text AS schema

        FROM pg_type
          INNER JOIN pg_namespace ON (typnamespace = pg_namespace.oid)

        WHERE
          typisdefined AND
          typelem = 0 AND
          pg_type.oid IN (SELECT unnest(#{sql_noncatalog_objects})) AND
          NOT pg_type.oid IN (SELECT unnest(#{sql_extension_objects}))
    SQL
    PostgresTools.fetch_sql_command(sql, '', logger).each{ |record|
      object = case record['typtype']
        when 'd' then 'DOMAIN'
        else 'TYPE'
      end
      comment_item = create_empty_comment_item()
      comment_item.identifier_noschema = record['identifier_noschema']
      comment_item.schema = record['schema']
      comment_item.schema = '' if comment_item.schema == 'public'
      comments[object] = {} unless comments.has_key?(object)
      comments[object][(comment_item.identifier + comment_item.arguments_nodefault).downcase] = comment_item
    }

    return comments
  end

  def self.create_empty_comment_item()
    comment_item = CommentItem.new
    comment_item.identifier_noschema = ''
    comment_item.schema = ''
    comment_item.arguments = ''
    comment_item.arguments_nodefault = ''
    comment_item.parsed_comment = ''
    comment_item.full_comment = ''
    return comment_item
  end

  def self.deep_dup(object)
    return Marshal.load(Marshal.dump(object))
  end

end
