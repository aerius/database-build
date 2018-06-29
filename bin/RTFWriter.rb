require 'rubygems'
begin
  require 'rtf'
rescue LoadError => e
  puts e.message
  puts 'Please run the following command to install this Ruby library:'
  puts '  gem install clbustos-rtf'
  exit
end

##
# Creates a RTF document to go along with a database build (release/dump).
# The RTF contains all database objects with their comments (as found in the SQL source files).
# It also lists the datasource files used for filling the tables (e.g. "natura2000_areas_20140414.txt").
#
class RTFWriter

  def self.create_rtf(filename, comments, datasources = {})

    styles = {}
    document = RTF::Document.new(RTF::Font.new(RTF::Font::ROMAN, 'Arial'))

    styles['Object'] = RTF::CharacterStyle.new
    styles['Object'].bold = true
    styles['Object'].font_size = 18 * 2

    styles['Identifier'] = RTF::CharacterStyle.new
    styles['Identifier'].bold = true
    styles['Identifier'].font_size = 12 * 2

    styles['Comment'] = RTF::CharacterStyle.new
    styles['Comment'].font_size = 10 * 2

    styles['Parameter'] = RTF::CharacterStyle.new
    styles['Parameter'].italic = true
    styles['Parameter'].foreground = RTF::Colour.new(0, 0, 128)
    styles['ReturnValue'] = RTF::CharacterStyle.new
    styles['ReturnValue'].italic = true
    styles['ReturnValue'].foreground = RTF::Colour.new(128, 0, 128)
    styles['SeeAlso'] = RTF::CharacterStyle.new
    styles['SeeAlso'].italic = true
    styles['SeeAlso'].foreground = RTF::Colour.new(0, 128, 0)
    styles['ToDo'] = RTF::CharacterStyle.new
    styles['ToDo'].italic = true
    styles['ToDo'].foreground = RTF::Colour.new(192, 0, 0)

    styles['CommentBold'] = RTF::CharacterStyle.new
    styles['CommentBold'].bold = true
    styles['CommentBold'].font_size = 10 * 2

    last_item = nil

    begin

      comments.sort.each{ |object, comment_items|

        last_item = nil

        document.paragraph { |p|
          p.apply(styles['Object']) { |c|
            c << object
          }
        }
        document.paragraph.line_break

        comment_items.sort.each{ |_, comment_item|
          identifier = comment_item.identifier
          arguments = comment_item.arguments

          full_identifier = identifier + arguments
          last_item = "#{object} #{full_identifier}"

          document.paragraph { |p|
            p.apply(styles['Identifier']) { |c|
              c << full_identifier
            }
          }
          document.paragraph { |p|
            p.apply(styles['Comment']) { |c|
              comment_lines = comment_item.full_comment.split($/)
              comment_lines.map!{ |comment_line|
                comment_line = comment_line.strip
              }
              comment_lines.pop while (!comment_lines.last.nil? and comment_lines.last.empty?)

              add_line_break = false
              comment_lines.each{ |comment_line|
                comment_bits = comment_line.split(' ')
                if (comment_bits.length > 0 and comment_bits[0].starts_with?('@')) then
                  c.line_break
                  add_line_break = false

                  if comment_bits[0] == '@param' then
                    c.apply(styles['Parameter']) { |c_param|
                      c_param << "Parameter [#{comment_bits[1]}]:  "
                    }
                    comment_line = comment_bits[2..(comment_line.size-1)].join(' ')
                  elsif comment_bits[0] == '@column' then
                    c.apply(styles['Parameter']) { |c_column|
                      c_column << "#{comment_bits[1]}:  "
                    }
                    comment_line = comment_bits[2..(comment_line.size-1)].join(' ')
                  elsif (comment_bits[0] == '@return' or comment_bits[0] == '@returns') then
                    c.apply(styles['ReturnValue']) { |c_return|
                      c_return << "Returns:  "
                    }
                    comment_line = comment_bits[1..(comment_line.size-1)].join(' ')
                  elsif comment_bits[0] == '@see' then
                    c.apply(styles['SeeAlso']) { |c_see|
                      c_see << "See Also:  "
                    }
                    comment_line = comment_bits[1..(comment_line.size-1)].join(' ')
                  elsif comment_bits[0] == '@todo' or comment_bits[0] == '@todo:' then
                    c.apply(styles['ToDo']) { |c_todo|
                      c_todo << "TODO:  "
                    }
                    comment_line = comment_bits[1..(comment_line.size-1)].join(' ')
                  end
                end

                if add_line_break then
                  c.line_break
                  add_line_break = false
                end

                c << comment_line

                add_line_break = true
              }
              c.line_break
            }
          }
        }

        document.paragraph.line_break
      }

      last_item = nil

      # Now the datasources

      table_datasources = {} # reverse hash
      datasources.each{ |datasource, tablename|
        table_datasources[tablename] = [] unless table_datasources.has_key?(tablename)
        table_datasources[tablename] << datasource
      }

      document.paragraph { |p|
        p.apply(styles['Object']) { |c|
          c << 'Data sources'
        }
      }
      document.paragraph.line_break

      table_datasources.sort.each { |table, datasourcefiles|
        document.paragraph { |p|
          p.apply(styles['Identifier']) { |c|
            c << table
            c.line_break
          }

          datasourcefiles.each { |datasource|

            last_item = "datasource #{datasource}"

            p.apply(styles['CommentBold']) { |c|
              c << File.basename(datasource)
              c.line_break
            }

            p.apply(styles['Comment']) { |c|
              infofile = datasource.chomp(File.extname(datasource)) + '.info'
              if File.exist?(infofile) then
                lines = File.readlines(infofile)
                lines.each_with_index { |line, index|
                  unless line.empty? && index == lines.size-1 then
                    c << line
                    c.line_break
                  end
                }
              end
            }

            last_item = nil
          }
        }
      }
    rescue
      puts "\nError parsing @ #{last_item}" unless last_item.nil?
      raise
    end

    # Write the result

    File.open(filename, 'w') { |file| file.write(document.to_rtf) }
  end

end
