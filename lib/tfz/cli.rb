# frozen_string_literal: true

module Tfz
  class CLI
    def self.start(args)
      if args.empty?
        # Launch TUI
        config = Config.new
        app = Tfz::UI::App.new(config)
        app.run
      else
        case args[0]
        when 'add'
          add_feed(args[1], args[2])
        when 'remove'
          remove_feed(args[1])
        when 'list'
          list_feeds
        when 'version', '-v', '--version'
          puts "tfz version #{VERSION}"
        when 'help', '-h', '--help'
          show_help
        else
          puts "Unknown command: #{args[0]}"
          show_help
        end
      end
    end

    def self.add_feed(url, category = nil)
      unless url
        puts "Error: URL required"
        puts "Usage: tfz add <url> [category]"
        exit 1
      end

      config = Config.new
      category ||= 'Uncategorized'
      config.add_feed(url, category: category)
      puts "Added feed: #{url} to category: #{category}"
    end

    def self.remove_feed(url)
      unless url
        puts "Error: URL required"
        puts "Usage: tfz remove <url>"
        exit 1
      end

      config = Config.new
      config.remove_feed(url)
      puts "Removed feed: #{url}"
    end

    def self.list_feeds
      config = Config.new
      if config.feeds.empty?
        puts "No feeds configured. Add one with: tfz add <url> [category]"
        return
      end

      puts "\nConfigured Feeds:\n\n"
      config.feeds_by_category.each do |category, feeds|
        puts "#{category}:"
        feeds.each do |feed|
          puts "  - #{feed['url']}"
        end
        puts
      end
    end

    def self.show_help
      puts <<~HELP
        Terminal Feedz (tfz) - A beautiful terminal feed reader

        Usage:
          tfz                      Launch the TUI feed reader
          tfz add <url> [category] Add a new feed
          tfz remove <url>         Remove a feed
          tfz list                 List configured feeds
          tfz version              Show version
          tfz help                 Show this help

        Examples:
          tfz add https://example.com/feed.xml Tech
          tfz add https://blog.example.com/rss.xml Blogs
          tfz remove https://example.com/feed.xml
      HELP
    end
  end
end
