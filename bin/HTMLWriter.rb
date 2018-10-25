require 'cgi'
require 'digest/sha2'
begin; require 'set'; rescue LoadError; require 'Set'; end;

##
# Creates a HTML document to go along with a database build (release/dump).
# The HTML contains all database objects with their comments (as found in the SQL source files).
# It also lists the datasource files used for filling the tables (e.g. "natura2000_areas_20140414.txt").
#
class HTMLWriter

  def self.create_html(filename, title, comments, datasources = {})

    last_item = nil

    html = ''
    html << "<!doctype html><html><head><meta charset=\"utf-8\">"
    html << "<title>#{title} psql-doc</title>"
    html << "<meta name=\"description\" content=\"#{title} psql-doc\">"

    html << <<-'END_HTML_HEADER'
<style>
body, table {font-size: 10pt; font-family: -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; line-height: 1.4em;}
a {text-decoration: none;}
.header {position: fixed; left: 0; top: 0; right: 0; height: 30px; line-height: 30px; font-size: 12pt; padding: 10px; white-space: nowrap; background-color: #eee;}
.header .generated {float: right; text-align: right; font-size: 8pt; color: silver;}
.header .title {display: inline-block; font-weight: bold; margin-right: 10px;}
.header .schemas {display: inline-block;}
.header .schemas .schema {margin-left: 10px; padding: 5px; cursor: pointer; color: white; border-radius: 4px; background-color: #088;}
.header .schemas .schema.active {background-color: #0aa;}
.toc {position: fixed; left: 0; top: 50px; bottom: 0; width: 280px; overflow: auto; font-size: 9pt; padding: 10px; white-space: nowrap;}
.toc .toc-entry {color: gray;}
.toc .toc-header {text-transform: lowercase; font-weight: bold; cursor: pointer;}
.toc .toc-block .toc-header::before {width: 12px; display: inline-block; font-weight: normal; margin-right: 4px;}
.toc .toc-block.collapsed .toc-header::before {content: "\25B6"; color: silver;}
.toc .toc-block.expanded .toc-header::before {content: "\25BC";}
.toc .toc-block {margin-bottom: 10px;}
.toc .toc-blockcontent {display: inline-block; overflow-y: hidden;}
.toc .toc-block.collapsed .toc-blockcontent {max-height: 0;}/*transition: max-height 0.3s ease-out;}*/
.toc .toc-block.expanded .toc-blockcontent {max-height: 9999999px;}/*transition: max-height 0.5s ease-in;}*/
.comments {position: fixed; left: 300px; top: 50px; right: 0; bottom: 0; padding: 20px; overflow-y: scroll;}
.comments .object {font-size: 20pt; line-height: 20pt; margin-top: 40px; margin-bottom: 5px; padding-bottom: 5px; font-style: italic; display: inline-block; border-bottom: 6px solid #ddd;}
.comments .object:first-child {margin-top: 0;}
.comments .block {margin-top: 1em; margin-bottom: 1em; padding: 10px; border: 1px solid #ddd;}
.comments .identifier {font-weight: bold; font-size: 12pt; padding-bottom: 5px; border-bottom: 1px solid #eee;}
.comments .identifier > span {float: left;}
.comments .schema {float: left; font-weight: normal; color: #066;}
.comments .arguments {font-weight: normal; font-style: italic; margin-left: 4px; color: #444;}
.comments .fileref {font-size: 8pt; font-weight: normal; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; direction: rtl; padding-left: 20px; text-align: right; color: darkgray;}
.comments .comment {padding-top: 5px;}
.comments .column, .comments .param, .comments .returns, .comments .seealso, .comments .todo {padding-left: 60px; text-indent: -30px;}
.comments .columnname, .comments .columntype, .comments .paramname, .comments .paramtype, .comments .returntype {font-family: Consolas, monospace;}
.comments .columnname, .comments .paramname {color: darkgreen;}
.comments .columntype, .comments .paramtype, .comments .returntype {font-style: italic; color: #8e9e8e;}
.comments .todo {padding-left: 30px; text-indent: -30px; margin-top: 10px;}
.comments .todo .todo-badge {color: white; font-size: 8pt; font-weight: bold; padding: 3px; margin-right: 4px; border-radius: 4px; background-color: #f60;}
.comments .note {font-style: italic; margin-top: 10px;}
.datasources-table {margin-top: 1em; margin-bottom: 1em; border-collapse: collapse; border: 1px solid #ddd;}
.datasources-table td, .datasources-table th { text-align: left; vertical-align: top; padding: 10px; border-bottom: 1px solid #eee;}
.datasources-table tr:last-child td, .datasources-table tr:last-child th { border-bottom: none;}
.datasources-table .datasource-info {font-size: 9pt; margin-bottom: 10px; color: gray;}
.datasources-table .datasource-info:last-child {margin-bottom: 0;}
</style>
<script type="text/javascript">
function showSchema(clickedButton, schemaName, all) {
  var items = document.querySelectorAll('[data-schema]');
  for (var i = 0; i < items.length; ++i) {
    items[i].style.display = (all || items[i].getAttribute('data-schema') == schemaName) ? '' : 'none';
  }
  var buttons = document.querySelectorAll('.schema');
  for (var i = 0; i < buttons.length; ++i) {
    buttons[i].className = (buttons[i] == clickedButton) ? 'schema active' : 'schema';
  }
}
function toggleTree(blockElement) {
  if (blockElement.className == 'toc-block expanded') {
    blockElement.className = 'toc-block collapsed';
  } else {
    blockElement.className = 'toc-block expanded';
  }
}
</script>
</head>
<body>
    END_HTML_HEADER

    toc = ''

    begin

      unique_schemas = Set.new
      comments.each{ |object, comment_items|
        comment_items.sort.each{ |_, comment_item|
          unique_schemas << comment_item.schema
        }
      }

      html << "<div class=\"header\">"
      html << "<div class=\"generated\">Generated on #{Time.now.strftime('%e-%b-%Y %H:%M:%S')}</div>"
      html << "<div class=\"title\">#{title}</div>"
      if unique_schemas.size > 0 then
        html << "<div class=\"schemas\">"
        html << "<span class=\"schema active\" onclick=\"showSchema(this,null,true);\">(all)</span>"
        unique_schemas.to_a.sort.each{ |schema|
          html << "<span class=\"schema\" onclick=\"showSchema(this,'#{schema}',false);\">#{schema.empty? ? 'public' : schema}</span>"
        }
        html << "</div>"
      end
      html << "</div>"

      html << "<div class=\"comments\">"
      comments.sort_by{ |object, _| ['SCHEMA','TABLE','VIEW','MATERIALIZED VIEW','FUNCTION','AGGREGATE','TYPE','DOMAIN'].index(object)}.each{ |object, comment_items|

        last_item = nil

        html << "<div class=\"object\">#{CGI.escapeHTML(object)}</div><div class=\"objectclearer\"></div>"

        toc << "<div class=\"toc-block expanded\">"
        toc << "<div class=\"toc-header\" onclick=\"toggleTree(this.parentElement)\">#{CGI.escapeHTML(object)}</div>"
        toc << "<div class=\"toc-blockcontent\">"

        comment_items.sort.each{ |_, comment_item|
          last_item = "#{object} #{comment_item.identifier}#{comment_item.arguments_nodefault}"

          anchor_name = get_anchor_name(object, comment_item)

          html << "<div class=\"block\" id=\"#{anchor_name}\" data-schema=\"#{comment_item.schema}\">"

          html << "<div class=\"identifier\">"
          html << "<span class=\"schema\">#{CGI.escapeHTML(comment_item.schema)}.</span>" unless comment_item.schema.empty? || object == 'SCHEMA'
          html << "<span>#{CGI.escapeHTML(comment_item.identifier_noschema)}</span>"
          html << "<span class=\"arguments\">#{CGI.escapeHTML(comment_item.arguments)}</span>" unless comment_item.arguments.empty?
          html << "<div class=\"fileref\">&lrm;#{CGI.escapeHTML(comment_item.file)}</div>" unless comment_item.file.nil? || comment_item.file.empty?
          html << "<div style=\"clear:both\"></div>"
          html << "</div>"

          toc << "<div class=\"toc-entry\" data-schema=\"#{comment_item.schema}\"><a href=\"##{anchor_name}\">#{CGI.escapeHTML(comment_item.identifier)}</a> #{CGI.escapeHTML(comment_item.arguments_nodefault)}</div>"

          html << "<div class=\"comment\">"
          html << escape_and_br(comment_item.parsed_comment)

          unless comment_item.todo.nil? then
            [*comment_item.todo].each{ |comment_item_todo_entry|
              html << "<div class=\"todo\"><span class=\"todo-badge\">TODO</span>#{escape_and_br(comment_item_todo_entry)}</div>"
            }
          end

          unless comment_item.columns.empty? then
            html << "<div class=\"note\">Columns:</div>"
            comment_item.columns.each{ |column, column_type, column_comment|
              html << "<div class=\"column\"><span class=\"columnname\">#{CGI.escapeHTML(column)}</span>"
              html << " <span class=\"columntype\">#{CGI.escapeHTML(column_type)}</span>" unless column_type.empty?
              html << " &ndash; <span class=\"columncomment\">#{escape_and_br(column_comment)}</span>" unless column_comment.empty?
              html << "</div>"
            }
          end

          unless comment_item.params.empty? then
            html << "<div class=\"note\">Parameters:</div>"
            comment_item.params.each{ |param, param_type, param_comment|
              html << "<div class=\"param\"><span class=\"paramname\">#{CGI.escapeHTML(param)}</span>"
              html << " <span class=\"paramtype\">#{CGI.escapeHTML(param_type)}</span>" unless param_type.empty?
              html << " &ndash; <span class=\"paramcomment\">#{escape_and_br(param_comment)}</span>" unless param_comment.empty?
              html << "</div>"
            }
          end

          unless comment_item.returns.nil? then
            html << "<div class=\"note\">Returns:</div><div class=\"returns\">"
            html << "<span class=\"returntype\">#{comment_item.returns[0]}</span>" unless comment_item.returns[0].empty?
            html << " &ndash; " unless comment_item.returns[0].empty? || comment_item.returns[1].empty?
            html << "#{escape_and_br(comment_item.returns[1])}" unless comment_item.returns[1].empty?
            html << "</div>"
          end

          unless comment_item.see.nil? then
            html << "<div class=\"note\">See also:</div><div class=\"seealso\">"
            comment_item_see_entries = [*comment_item.see]
            comment_item_see_entries.each_index{ |idx|
              html << ", " if idx > 0
              see_object, see_comment_item = find_item(comments, comment_item_see_entries[idx])
              if see_comment_item.nil? then
                html << escape_and_br(comment_item_see_entries[idx])
              else
                see_anchor_name = get_anchor_name(see_object, see_comment_item)
                html << "<a href=\"##{see_anchor_name}\">#{CGI.escapeHTML(see_comment_item.identifier + see_comment_item.arguments_nodefault)}</a>"
              end
            }
            html << "</div>"
          end

          html << "</div></div>"
        }

        toc << "</div></div>"
      }

      last_item = nil

      ###########################
      # Now the datasources
      ###########################

      table_datasources = {} # reverse hash
      datasources.each{ |datasource, tablename|
        table_datasources[tablename] = [] unless table_datasources.has_key?(tablename)
        table_datasources[tablename] << datasource
      }

      html << "<div class=\"object\">DATA SOURCES</div><div class=\"objectclearer\"></div>"
      html << "<table class=\"datasources-table\">"

      toc << "<div class=\"toc-block expanded\">"
      toc << "<div class=\"toc-header\" onclick=\"toggleTree(this.parentElement)\">DATA SOURCES</div>"
      toc << "<div class=\"toc-blockcontent\">"

      table_datasources.sort.each { |table, datasourcefiles|

        schema = table.include?('.') ? table.split('.')[0] : ''
        anchor_name = 'datasource-' + table.downcase.gsub('.', '-').gsub('_', '-')

        html << "<tr id=\"#{anchor_name}\" data-schema=\"#{schema}\"><th>"
        table_comment_item = find_table(comments, table)
        if table_comment_item.nil? then
          html << CGI.escapeHTML(table)
        else
          table_anchor_name = get_anchor_name('TABLE', table_comment_item)
          html << "<a href=\"##{table_anchor_name}\">#{CGI.escapeHTML(table)}</a>"
        end
        html << "</th><td>"

        toc << "<div class=\"toc-entry\" data-schema=\"#{schema}\"><a href=\"##{anchor_name}\">#{CGI.escapeHTML(table)}</a></div>"

        datasourcefiles.each { |datasource|
          last_item = "datasource #{datasource}"

          html << "<div>#{CGI.escapeHTML(File.basename(datasource))}</div>"

          infofile = datasource.chomp(File.extname(datasource)) + '.info'
          if File.exist?(infofile) then
            info = File.readlines(infofile).join("\n").strip
            html << "<div class=\"datasource-info\">#{escape_and_br(info)}</div>"
          end

          last_item = nil
        }

        html << "</td></tr>"
      }

      toc << "</div></div>"
      html << "</table>"

    rescue
      puts "\nError parsing @ #{last_item}" unless last_item.nil?
      raise
    end

    html << "</div>"
    html << "<div class=\"toc\">" << toc << "</div>"

    html << "</body></html>"

    # Write the result

    File.open(filename, 'w') { |file| file.write(html) }
  end

 private

  def self.get_anchor_name(object, comment_item)
    # generate unique but reproducable anchor name for an item
    anchor_name = "#{object}-#{comment_item.identifier}"
    anchor_name << "-" << Digest::SHA2.hexdigest(comment_item.arguments)[0..15] unless comment_item.arguments.empty?
    anchor_name = anchor_name.downcase.gsub('.', '-').gsub('_', '-')
    return anchor_name
  end

  def self.find_item(comments, term)
    # best guess for an item referenced via @see
    comments.each{ |object, comment_items|
      comment_items.sort.each{ |_, comment_item|
        return object, comment_item if term == comment_item.identifier + comment_item.arguments_nodefault || term == comment_item.identifier + comment_item.arguments
      }
    }
    comments.each{ |object, comment_items|
      comment_items.sort.each{ |_, comment_item|
        return object, comment_item if term == comment_item.identifier_noschema + comment_item.arguments_nodefault || term == comment_item.identifier_noschema + comment_item.arguments
      }
    }
    comments.each{ |object, comment_items|
      comment_items.sort.each{ |_, comment_item|
        return object, comment_item if term == comment_item.identifier || term == comment_item.identifier + '()'
      }
    }
    comments.each{ |object, comment_items|
      comment_items.sort.each{ |_, comment_item|
        return object, comment_item if term == comment_item.identifier_noschema || term == comment_item.identifier_noschema + '()'
      }
    }
    return nil, nil
  end

  def self.find_table(comments, term)
    if comments.has_key?('TABLE') then
      comments['TABLE'].sort.each{ |_, comment_item|
        return comment_item if term == comment_item.identifier
      }
    end
    return nil
  end

  def self.escape_and_br(str)
    return CGI.escapeHTML(str).gsub("\n", '<br>').gsub(/https?\:\/\/\S+/, '<a href="\0" target="_blank">\0</a>')
  end

end
