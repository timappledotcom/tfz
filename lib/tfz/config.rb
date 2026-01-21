# frozen_string_literal: true

module Tfz
  class Config
    CONFIG_DIR = File.expand_path('~/.config/tfz')
    CACHE_DIR = File.expand_path('~/.cache/tfz')
    CONFIG_FILE = File.join(CONFIG_DIR, 'config.yml')
    READ_ARTICLES_FILE = File.join(CACHE_DIR, 'read_articles.yml')

    attr_reader :feeds, :categories, :read_articles

    def initialize
      setup_directories
      load_config
      load_read_articles
    end

    def setup_directories
      FileUtils.mkdir_p(CONFIG_DIR)
      FileUtils.mkdir_p(CACHE_DIR)
    end

    def load_config
      if File.exist?(CONFIG_FILE)
        data = YAML.load_file(CONFIG_FILE)
        @feeds = data['feeds'] || []
        @categories = data['categories'] || {}
      else
        @feeds = []
        @categories = {}
        save_config
      end
    end

    def save_config
      data = {
        'feeds' => @feeds,
        'categories' => @categories
      }
      File.write(CONFIG_FILE, YAML.dump(data))
    end

    def add_feed(url, category: 'Uncategorized')
      @feeds << { 'url' => url, 'category' => category }
      @categories[category] ||= []
      @categories[category] << url unless @categories[category].include?(url)
      save_config
    end

    def remove_feed(url)
      feed = @feeds.find { |f| f['url'] == url }
      return unless feed

      @feeds.delete(feed)
      @categories.each do |_cat, urls|
        urls.delete(url)
      end
      save_config
    end

    def feeds_by_category
      result = {}
      @feeds.each do |feed|
        category = feed['category'] || 'Uncategorized'
        result[category] ||= []
        result[category] << feed
      end
      result
    end

    def load_read_articles
      if File.exist?(READ_ARTICLES_FILE)
        @read_articles = YAML.load_file(READ_ARTICLES_FILE) || []
      else
        @read_articles = []
      end
    end

    def save_read_articles
      File.write(READ_ARTICLES_FILE, YAML.dump(@read_articles))
    end

    def mark_as_read(article_id)
      @read_articles << article_id unless @read_articles.include?(article_id)
      save_read_articles
    end

    def mark_as_unread(article_id)
      @read_articles.delete(article_id)
      save_read_articles
    end

    def read?(article_id)
      @read_articles.include?(article_id)
    end

    def category_names
      feeds_by_category.keys.sort
    end

    def add_category(name)
      @categories[name] ||= []
      save_config
    end

    def remove_category(name)
      return if name == 'Uncategorized'
      
      # Move feeds to Uncategorized
      @feeds.each do |feed|
        feed['category'] = 'Uncategorized' if feed['category'] == name
      end
      @categories.delete(name)
      save_config
    end

    def rename_category(old_name, new_name)
      return if old_name == 'Uncategorized'
      
      @feeds.each do |feed|
        feed['category'] = new_name if feed['category'] == old_name
      end
      @categories[new_name] = @categories.delete(old_name) if @categories[old_name]
      save_config
    end

    def update_feed_category(url, new_category)
      feed = @feeds.find { |f| f['url'] == url }
      return unless feed
      
      old_category = feed['category']
      feed['category'] = new_category
      
      @categories[old_category]&.delete(url)
      @categories[new_category] ||= []
      @categories[new_category] << url unless @categories[new_category].include?(url)
      
      save_config
    end
  end
end
