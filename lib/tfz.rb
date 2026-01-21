# frozen_string_literal: true

require 'feedjira'
require 'http'
require 'yaml'
require 'fileutils'
require 'tty-reader'
require 'tty-screen'
require 'tty-cursor'
require 'tty-box'
require 'pastel'
require 'reverse_markdown'
require 'tty-markdown'
require 'readability'
require 'nokogiri'
require 'htmlentities'
require 'rouge'

# Force unbuffered output for TUI
$stdout.sync = true

require_relative 'tfz/version'
require_relative 'tfz/config'
require_relative 'tfz/feed_manager'
require_relative 'tfz/feed_fetcher'
require_relative 'tfz/ui/app'
require_relative 'tfz/cli'

module Tfz
  class Error < StandardError; end
end
