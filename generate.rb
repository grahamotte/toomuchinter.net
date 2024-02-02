require 'rubygems'
require 'bundler/setup'
Bundler.require

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
      url:,
      title:,
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
  .each { |x| x.timestamp = Time.parse(x.timestamp) }

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

items
  .each { |x| x.digest ||= Digest::SHA256.hexdigest(x.url) }
  .each { |x| x.wbm ||= nil; x.wbm_tries ||= 0 }
  .each { |x| x.png ||= nil; x.png_tries ||= 0 }
  .each { |x| x.pdf ||= nil; x.pdf_tries ||= 0 }

#
# archival
#

# def try
#   yield
# rescue StandardError => e
#   puts e.message
#   puts e.backtrace
# end

# def browse(url)
#   browser = nil
#   try do
#     browser = Ferrum::Browser.new(window_size: [1200, 1200], headless: true, timeout: 60)
#     browser.go_to(url)
#     sleep(10)
#     yield(browser)
#   end
# ensure
#   browser&.quit
# end

# items
#   .select { |x| x.wbm.nil? }
#   .select { |x| x.wbm_tries < 8 }
#   .sample(2)
#   .each do |item|
#     puts "wbm #{item.url}"
#     item.wbm_tries += 1
#     try do
#       item.wbm = RestClient
#         .get("https://archive.org/wayback/available?url=#{item.url}")
#         .body
#         .then { |x| JSON.parse(x, symbolize_names: true) }
#         .dig(:archived_snapshots, :closest, :url)
#     end
#   end

# items
#   .select { |x| x.pdf.nil? }
#   .select { |x| x.pdf_tries < 8 }
#   .sample(2)
#   .each do |item|
#     puts "pdf #{item.url}"
#     item.pdf_tries += 1
#     item.pdf ||= "snapshots/#{item.digest}.pdf"
#     browse(item.url) { |x| x.pdf(path: item.pdf) }
#   end

# items
#   .select { |x| x.png.nil? }
#   .select { |x| x.png_tries < 8 }
#   .sample(2)
#   .each do |item|
#     puts "png #{item.url}"
#     item.png_tries += 1
#     item.png ||= "snapshots/#{item.digest}.png"
#     browse(item.url) { |x| x.screenshot(path: item.png, full: true) }
#   end

#
# save
#

items
  .reverse
  .map
  .with_index do |item, i|
    {
      id: i + 1,
      digest: Digest::SHA256.hexdigest(item.url),
      url: item.url,
      title: item.title,
      timestamp: item.timestamp,
      wbm: item.wbm,
      wbm_tries: item.wbm_tries,
      png: item.png && File.exist?(item.png) ? item.png : nil,
      png_tries: item.png_tries,
      pdf: item.pdf && File.exist?(item.pdf) ? item.pdf : nil,
      pdf_tries: item.png_tries,
    }
  end
  .then { |x| JSON.pretty_generate(x) }
  .then { |x| File.write(items_path, x) }

#
# index.html
#

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
      header {
        font-weight: bold;
      }
      ol {
        list-style-position: outside;
        padding-left: 0;
      }
      li {
        margin-bottom: 1.5rem;
      }
      a {
        color: #07beb8;
        text-decoration: none;
      }
      a:hover {
        background: #07beb8;
        color: #fff;
      }
      a.secondary {
        color: #999;
        text-decoration: none;
      }
      a.secondary:hover {
        background: #999;
        color: #fff;
      }
      .text-small {
        font-size: 0.75em;
      }
      .text-tiny {
        font-size: 0.5em;
      }
    </style>
  HTML
end

def item_html(item)
  <<~HTML
    <li>
      <a href="#{item.url}" target="_blank">#{CGI.escape_html(item.title)}</a>
      <br /><span class="text-small">#{item.timestamp.strftime('%Y-%m-%d %H:%M:%S')}</span>
      #{item.wbm ? "<a href=\"#{item.wbm}\" target=\"_blank\" class=\"text-tiny\">WBM</a>" : nil}
      #{item.png && File.exist?(item.png) ? "<a href=\"/#{item.png}\" target=\"_blank\" class=\"text-tiny\">PNG</a>" : nil}
      #{item.pdf && File.exist?(item.pdf) ? "<a href=\"/#{item.pdf}\" target=\"_blank\" class=\"text-tiny\">PDF</a>" : nil}
    </li>
  HTML
  #  {item.archive_url == 'none' ? nil : "<a class=\"text-small\" href=\"#{item.archive_url}\" target=\"_blank\">A</a>"}
end

index_html = <<~HTML
  <!DOCTYPE html>
  <html>
    <head>
      <meta charset="utf-8">
      <title>toomuchinter.net</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <link rel="alternate" type="application/rss+xml" title="toomuchinter.net RSS feed" href="https://toomuchinter.net/feed.xml">
      #{style_html}
    </head>
    <body>
      <header>i took too much inter.net</header>
      <br />
      <ol reversed>
        #{items.first(256).map { |x| item_html(x) }.join("\n")}
      </ol>
      <br />
      <a class="secondary" href="https://toomuchinter.net/feed.xml">feed</a>
      <br />
      <a class="secondary" href="mailto:hey@toomuchinter.net">send me cool stuff</a>
    </body>
  </html>
HTML

File.write('index.html', index_html)

#
# feed.xml
#

def feet_item_xml(item)
  <<~XML
    <item>
      <title><![CDATA[#{item.title}]]></title>
      <description></description>
      <link><![CDATA[#{item.url}]]></link>
      <pubDate>#{item.timestamp.rfc2822}</pubDate>
      <guid>#{Digest::SHA256.hexdigest(item.url)}</guid>
    </item>
  XML
end

feed_xml = <<~XML
  <?xml version="1.0" encoding="UTF-8" ?>
  <rss version="2.0">
    <channel>
      <title>toomuchinter.net</title>
      <description>toomuchinter.net</description>
      <link>https://toomuchinter.net</link>
      <lastBuildDate>#{Date.today.to_time.rfc2822}</lastBuildDate>
      <pubDate>#{Date.today.to_time.rfc2822}</pubDate>
      <ttl>1800</ttl>

      #{items.first(256).map { |x| feet_item_xml(x) }.join("\n")}

    </channel>
  </rss>
XML

File.write('feed.xml', feed_xml)

#
# commit
#

system('git add -A')
system('git commit -m generate')
system('git push')
