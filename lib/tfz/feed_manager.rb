# frozen_string_literal: true

require 'digest'

module Tfz
  class FeedManager
    attr_reader :config, :feeds_data

    def initialize(config)
      @config = config
      @feeds_data = []
    end

    def refresh_all
      @feeds_data = []
      @config.feeds.each do |feed_info|
        feed_data = FeedFetcher.fetch(feed_info['url'])
        next if feed_data.nil? || feed_data[:error]

        feed_data[:category] = feed_info['category'] || 'Uncategorized'
        @feeds_data << feed_data
      end
      @feeds_data
    end

    def all_entries_by_category
      result = {}
      @feeds_data.each do |feed|
        category = feed[:category]
        result[category] ||= []
        result[category].concat(feed[:entries])
      end
      
      # Sort by published date
      result.each do |category, entries|
        result[category] = entries.sort_by { |e| e[:published] || Time.at(0) }.reverse
      end
      
      result
    end

    def all_entries(category: nil, read_status: :all)
      entries = @feeds_data.flat_map do |feed|
        next [] if category && feed[:category] != category
        feed[:entries]
      end
      
      # Filter by read status
      entries = filter_by_read_status(entries, read_status)
      
      entries.sort_by { |e| e[:published] || Time.at(0) }.reverse
    end

    def generate_article_id(entry)
      # Generate unique ID from URL and published date
      data = "#{entry[:url]}|#{entry[:published]}"
      Digest::SHA256.hexdigest(data)[0..15]
    end

    private

    def filter_by_read_status(entries, status)
      case status
      when :unread
        entries.reject { |e| @config.read?(generate_article_id(e)) }
      when :read
        entries.select { |e| @config.read?(generate_article_id(e)) }
      else
        entries
      end
    end
  end
end
