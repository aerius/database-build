##
# Representation of a parsed comment for a database object
#
class CommentItem
  attr_accessor :identifier_noschema, :schema, :arguments, :arguments_nodefault
  attr_accessor :full_comment, :parsed_comment
  attr_accessor :params, :columns
  attr_accessor :returns, :see, :todo, :file

  def initialize
    @params = []
    @columns = []
  end

  def identifier
    if @schema == '' || @schema == @identifier_noschema then
      @identifier_noschema
    else
      @schema + '.' + @identifier_noschema
    end
  end
end

##
# Utility class for finding all database object comments that are written in the SQL
# source files according to a Javadoc-like format.
#
class CommentCollector

  # Walk through source files and collect all comments for database objects.
  def self.collect(logger, scanned_sql_path, common_sql_path, root_path)
    comments = {}

    Dir[scanned_sql_path + '**/*.sql'].each{ |input_sql_filename|
      processed_files = PostgresTools.process_sql_file_and_return_separate_files(input_sql_filename, common_sql_path)

      comment = ''
      contents = ''
      in_comment_block = 0
      before_was_a_comment_block = false

      processed_files.each{ |processed_sql_file|
        processed_sql_file.contents.each_line do |line|
          line.strip!
          unless line.empty? then

            if line.starts_with?('/*') then
              in_comment_block += 1
              n = line.starts_with?('/**') ? 3 : 2
              comment = line[n, line.length-n].strip if in_comment_block == 1     # only collect comment when no nested comments

            elsif in_comment_block > 0 then
              if line.ends_with?('*/') then
                in_comment_block -= 1
                if in_comment_block == 0 then
                  n = line.ends_with?('**/') ? 3 : 2
                  line = line[0, line.length-n].strip
                  line = line[1, line.length-1].strip if line.starts_with?('*')
                  comment << "\n" unless line.empty? || comment.empty?
                  comment << line
                  before_was_a_comment_block = true
                end
              elsif in_comment_block == 1 then
                line = line[1, line.length-1] if line.starts_with?('*')
                line.strip!
                comment << "\n" unless comment.empty?
                comment << line
              end

            elsif before_was_a_comment_block then
              contents << ' ' + line
              object = nil
              identifier = nil
              arguments = nil
              if /^\s*CREATE\s+(MATERIALIZED VIEW)\s+([\w\.]+)\s*/i.match(contents) ||
                 /^\s*CREATE.*\s+(TABLE|VIEW|TYPE|DOMAIN|SCHEMA)\s+([\w\.]+)\s*/i.match(contents) ||
                 /^\s*CREATE.*\s+(FUNCTION|AGGREGATE)\s+([\w\.]+)\s*(\(.*\))\s*/i.match(contents) then
                object = $1.upcase
                identifier = $2
                arguments = $3 || ''

                unless identifier.nil? || identifier.downcase == comment.downcase then
                  file = Pathname.new(processed_sql_file.filename).relative_path_from(Pathname.new(root_path)).to_s
                  process_comment_block(logger, comments, object, identifier, arguments, comment, file, processed_sql_file.default_schema)
                end
              end

              if !contents.strip.empty? then
                before_was_a_comment_block = false
                comment = ''
                contents = ''
              end
            end #before_was_a_comment_block
          end #unless line empty
        end #each_line
      } #each processed file
    } #each file

    return comments
  end

 private

  def self.process_comment_block(logger, comments, object, identifier, arguments, comment, file, default_schema = nil)
    comment_item = create_comment_item(object, identifier, arguments)
    comment_item.file = file

    comment_item.schema = default_schema if !default_schema.nil? && comment_item.schema == '' && object != 'SCHEMA'

    comment_lines = split_comment_without_header(logger, comment, identifier)
    comment_item.full_comment = fix_wrapping(comment_lines)

    parse_comment_tags(logger, comment_item)

    comment_item.full_comment += "\n\n" unless comment_item.full_comment.empty?
    comment_item.full_comment += "@file " + file

    comments[object] = {} unless comments.has_key?(object)
    comments[object][(comment_item.identifier + comment_item.arguments_nodefault).downcase] = comment_item
  end

  def self.split_comment_without_header(logger, comment, identifier)
    comment_lines = comment.strip.split("\n")
    headername = identifier
    altheadername = identifier
    altheadername = altheadername.split('.')[1] if altheadername.include?('.')
    if (comment_lines.size >= 2) && ((comment_lines[1] == '-' * comment_lines[1].length) || (comment_lines[1] == '=' * comment_lines[1].length)) then
      header_mismatch = (comment_lines[0] != headername && comment_lines[0] != altheadername)
      logger.major_hint "sql comment for \"#{headername}\" has header \"#{comment_lines[0]}\"" if header_mismatch
      logger.minor_hint "sql comment for \"#{headername}\" has wrong dashed line length" if !header_mismatch && comment_lines[0].length != comment_lines[1].length
      logger.minor_hint "sql comment for \"#{headername}\" has wrong dashed line style, use '-' character" if !header_mismatch && !comment_lines[1].empty? && comment_lines[1][0] != '-'
      comment_lines.delete_at(1)
      comment_lines.delete_at(0)
    elsif (comment_lines.size >= 1) && (comment_lines[0] == headername || comment_lines[0] == altheadername) then
      logger.major_hint "sql comment for \"#{comment_lines[0]}\" has no dashed line"
      comment_lines.delete_at(0)
    end
    return comment_lines
  end

  def self.fix_wrapping(comment_lines)
    full_comment = ''
    comment_lines.each_with_index{ |comment_line, idx|
      full_comment << comment_line
      next_line = (idx + 1) < comment_lines.size ? comment_lines[idx + 1] : ''
      if comment_line.empty? || comment_line.length <= 50 ||
          comment_line.end_with?('.') || comment_line.end_with?(':') ||
          comment_line.end_with?('<br>') ||
          next_line.start_with?('@') then
        full_comment.chomp!('<br>')
        full_comment << "\n"
      else
        full_comment << " "
      end
    }
    return full_comment.strip
  end

  def self.create_comment_item(object, identifier, arguments)
    comment_item = CommentItem.new
    comment_item.identifier_noschema = identifier.include?('.') ? identifier.split('.')[1] : identifier
    comment_item.schema = identifier.include?('.') ? identifier.split('.')[0] : ''
    comment_item.schema = identifier if object == 'SCHEMA'
    comment_item.schema = '' if comment_item.schema == 'public'
    comment_item.arguments = arguments
    comment_item.arguments_nodefault = arguments.gsub(/\s*=\s*((E?'\S*')|(\w+))\s*/i, '') # strip default values of optional parameters
    return comment_item
  end

  def self.parse_comment_tags(logger, comment_item)
    accepted_keywords = ['@param', '@column', '@return', '@returns', '@see', '@todo', '@file']
    tagless_comment = ''
    current_keyword = nil
    current_keyword_argument = nil
    before_keywords_found = true
    keyword_comment_lines = []

    comment_lines = comment_item.full_comment.split("\n")
    comment_lines.each_with_index{ |comment_line, idx|
      next_line = (idx + 1) < comment_lines.size ? comment_lines[idx + 1] : nil

      if comment_line.start_with?(*accepted_keywords) then
        # prepare current keyword
        comment_bits = comment_line.split(' ')
        prev_keyword = current_keyword
        current_keyword = comment_bits[0]
        if current_keyword == '@param' || current_keyword == '@column' then
          if comment_bits.size < 2 then
            logger.major_hint "sql comment for \"#{comment_item.identifier}#{comment_item.arguments_nodefault}\" has #{current_keyword} without argument"
            current_keyword = prev_keyword
          else
            current_keyword_argument = comment_bits[1]
            keyword_comment_lines = [comment_bits[2..(comment_bits.size-1)].join(' ').strip]
          end
        else
          current_keyword_argument = nil
          keyword_comment_lines = [comment_bits[1..(comment_bits.size-1)].join(' ').strip]
        end
        before_keywords_found = false unless current_keyword.nil?

      elsif !current_keyword.nil? then
        # append comment of current keyword
        keyword_comment_lines << comment_line
      end

      if !current_keyword.nil? && (next_line.nil? || next_line.start_with?(*accepted_keywords)) then
        # finish current keyword: process comment
        fixed_comment = fix_wrapping(keyword_comment_lines)
        if current_keyword == '@param' then
          comment_item.params << [current_keyword_argument, '', fixed_comment]
        elsif current_keyword == '@column' then
          comment_item.columns << [current_keyword_argument, '', fixed_comment]
        elsif current_keyword == '@return' || current_keyword == '@returns' then
          comment_item.returns = ['', fixed_comment]
        elsif current_keyword == '@see' then
          comment_item.see = comment_item.see.nil? ? fixed_comment : [*comment_item.see] + [fixed_comment]
        elsif current_keyword == '@todo' || current_keyword == '@todo:' then
          comment_item.todo = comment_item.todo.nil? ? fixed_comment : [*comment_item.todo] + [fixed_comment]
        end
        current_keyword = nil
        keyword_comment_lines = []
      end

      tagless_comment << comment_line << "\n" if before_keywords_found
    }
    comment_item.parsed_comment = tagless_comment.strip
  end

end
