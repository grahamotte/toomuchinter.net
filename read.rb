require 'pry'
require 'extlz4'
require 'oj'
require 'ostruct'
require 'json'
require 'fileutils'
require 'sqlite3'
require 'time'

#
# places
#

tmp_dir = File.join(__dir__, 'tmp')
tmp_places_path = File.join(tmp_dir, 'places.sqlite')
ff_places_path = File
  .expand_path('~/Library/Application Support/Firefox/Profiles/*/places.sqlite')
  .then { |x| Dir.glob(x) }
  .first

FileUtils.rm_rf(tmp_dir)
FileUtils.mkdir(tmp_dir)
FileUtils.cp(ff_places_path, tmp_places_path)

places = SQLite3::Database
  .new(tmp_places_path)
  .execute(
    <<~SQL,
      select
        p.url,
        b.title,
        b.lastModified
      from moz_bookmarks b
      left join moz_places p on b.fk = p.id
      left join moz_bookmarks f on f.id = b.parent
      where b.type = 1
        and f.type = 2 and f.title = 'GOOD'
    SQL
  )
  .map do |url, title, timestamp|
    OpenStruct.new(
      url: url,
      title: title,
      timestamp: Time.at(timestamp / 1_000_000),
    )
  end
  .sort_by(&:timestamp)
  .reverse

FileUtils.rm_rf(tmp_dir)

#
# items
#

items_path = File.join(__dir__, 'items.json')
items = File
  .read(items_path)
  .then { |x| JSON.parse(x) }
  .map { |x| OpenStruct.new(x) }

#
# merge
#

items_index = items.group_by(&:url)
places_index = places.group_by(&:url)
items = (items_index.keys + places_index.keys)
  .uniq
  .map { |url| [items_index[url], places_index[url]].flatten.compact.first }
  .sort_by(&:timestamp)
  .reverse
File.write(items_path, JSON.pretty_generate(items.map(&:to_h)))

#
# index
#
# <link rel="alternate" type="application/rss+xml" title="RSS Feed for J.Soliday" href="https://www.jsoliday.com/feed.rss">

def style_html
  <<~HTML
      <style>
      body {
        margin: 40px auto;
        max-width: 650px;
        line-height: 1.6;
        font-size: 1em;
        color: #444;
        padding: 0 10px;
        font-family: monospace, monospace;
      }
      h1, h2, h3{
        line-height:1.2;
      }
      a {
        color: #07beb8;
        text-decoration: none;
      }
      a:hover {
        background: #07beb8;
        color: #fff;
      }
      header {
        font-weight: bold;
      }
      .text-small {
        font-size: 0.75em;
      }
    </style>
  HTML
end

def item_html(item)
  <<~HTML
    <p>
      <div><a href="#{item.url}" target="_blank">#{item.title}</a></div>
      <div class="text-small">#{Time.parse(item.timestamp).strftime('%Y-%m-%d %H:%M:%S')}</div>
    </p>
  HTML
end

index_html = <<~HTML
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8">
      <title>toomuchinter.net</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      #{style_html}
    </head>
    <body>
      <header>i took toomuchinter.net</header>
      #{items.map { |x| item_html(x) }.join("\n")}
    </body>
  </html>
HTML

File.write('index.html', index_html)
