# frozen_string_literal: true

module Tfz
  class FeedFetcher
    def self.fetch(url)
      response = HTTP.timeout(10).get(url)
      return nil unless response.status.success?

      feed = Feedjira.parse(response.body.to_s)
      normalize_feed(feed, url)
    rescue => e
      { error: e.message, url: url }
    end

    def self.normalize_feed(feed, url)
      {
        title: feed.title,
        url: url,
        entries: feed.entries.map do |entry|
          {
            title: entry.title,
            url: entry.url,
            published: entry.published,
            summary: entry.summary || entry.content || '',
            content: entry.content || entry.summary || '',
            author: entry.author || feed.title
          }
        end
      }
    end
  end
end
