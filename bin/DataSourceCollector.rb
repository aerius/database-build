require 'PostgresTools'

##
# Utility class for finding all datasource filenames (.txt) in the load-data SQL files.
#
class DataSourceCollector

  # Walk through load sql files of a certain product and find its datasource txt filenames (including references to common).
  # parse_path is the path to e.g. database\src\data\sql\product\
  def self.collect(logger, parse_path, common_data_path, data_folder = nil)
    return parse_load_rb(logger, parse_path, common_data_path, data_folder)
  end

 private

  # Given a folder, open the load.rb in there and parse the SQL files and folders it references
  def self.parse_load_rb(logger, parse_path, common_data_path, data_folder = nil)
    data_folder.chomp!('/') unless data_folder.nil? # for search & replace

    parse_path = parse_path.fix_pathname
    rb_filename = parse_path + 'load.rb'
    logger.error "Could not find file: #{rb_filename}" unless File.exist?(rb_filename)

    logger.log "Parse for used load-data SQL files: #{rb_filename}"

    sql_files = []
    in_comment = false
    File.open(rb_filename, 'r').each { |line|

      line.strip!

      in_comment = true if line == '=begin'
      in_comment = false if line == '=end'

      if !in_comment && line.include?('#') then
        line = str_delete_range(line, '#', nil)
      end

      if !in_comment then
        if line =~ /run\_sql\s+[\'\"](.+)[\'\"]/i then
          sql_files << parse_path + $1
        elsif line =~ /run\_sql\_folder\s+[\'\"](.+)[\'\"]/i then
          Dir[parse_path + $1 + '/**/*.sql'].each { |sql_filename|
            sql_files << sql_filename
          }
        end
      end
    }

    datasources = {}
    sql_files.each { |sql_filename|
      sql_filename += '.sql' unless sql_filename.downcase.end_with?('.sql')
      logger.log "Parse for data sources: #{sql_filename}"
      sql_contents = PostgresTools.process_sql_file(sql_filename, common_data_path)
      datasources.merge!(process_sql(sql_contents, data_folder))
    }

    return datasources
  end

  # Go through contents of a SQL file and detect data sources
  def self.process_sql(sql_contents, data_folder)
    datasources = {}
    in_comment = false

    sql_contents.each_line { |line|

      line.strip!

      if !in_comment && line.include?('--') then
        line = str_delete_range(line, '--', nil)
      end

      if !in_comment && line.include?('/*') then
        if line.include?('*/') && line.index('/*') < line.index('*/') then
          line = str_delete_range(line, '/*', '*/')
        else
          line = str_delete_range(line, '/*', nil)
          in_comment = true
        end
      elsif in_comment && line.include?('*/') then
        line = str_delete_range(line, nil, '*/')
        in_comment = false
      end

      if !in_comment && line =~ /\(.*\'(.*)\'.*,\s*\'(\{data\_folder\}.+\.txt)\'/i then
        table = $1
        datasource = $2
        datasource.gsub!('{data_folder}', data_folder) unless data_folder.nil?
        datasources[datasource] = table
      end
    }

    return datasources
  end

  def self.str_delete_range(str, from, to)
    if !from.nil? && to.nil? then
      p = str.index(from)
      return str[0, p] unless p.nil?
    elsif from.nil? && !to.nil? then
      p = str.index(to)
      return str[(p+to.length)..(str.length-1)] unless p.nil?
    elsif !from.nil? && !to.nil? then
      p1 = str.index(from)
      p2 = str.index(to)
      return str[0, p1] + str[(p2+to.length)..(str.length-1)] unless p1.nil? || p2.nil?
    end
    return str
  end
end