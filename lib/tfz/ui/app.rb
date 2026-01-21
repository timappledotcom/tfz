# frozen_string_literal: true

module Tfz
  module UI
    class App
      def initialize(config)
        @config = config
        @feed_manager = FeedManager.new(config)
        @cursor = TTY::Cursor
        @reader = TTY::Reader.new(interrupt: :exit)
        @pastel = Pastel.new
        
        # Force unbuffered output
        $stdout.sync = true
        
        # State management
        @mode = :main_menu
        @selected_index = 0
        @scroll_offset = 0
        
        # Feed list state
        @entries = []
        @current_category = nil
        @read_filter = :all  # :all, :unread, :read
        
        # Reader state
        @reader_scroll = 0
        @content_lines = []
        
        # Menu items
        @menu_items = []
      end

      def run
        setup_screen
        render_loop
      rescue Interrupt
        cleanup_screen
      ensure
        cleanup_screen
      end

      private

      def setup_screen
        $stdout.write "\033[?1049h"  # Switch to alternate screen buffer
        $stdout.write "\033[?25l"    # Hide cursor
        $stdout.write "\033[2J"      # Clear screen
        $stdout.write "\033[1;1H"    # Move to home position (1-indexed)
      end

      def cleanup_screen
        $stdout.write "\033[?25h"    # Show cursor
        $stdout.write "\033[?1049l"  # Switch back from alternate screen buffer
      end
      
      def clear_and_home
        $stdout.write "\033[2J"      # Clear screen
        $stdout.write "\033[1;1H"    # Move to home position (1-indexed)
      end
      
      def write_line(text)
        $stdout.write text
        $stdout.write "\r\n"
      end

      def render_loop
        loop do
          case @mode
          when :main_menu
            draw_main_menu
          when :category_menu
            draw_category_menu
          when :feed_list
            draw_feed_list
          when :subscriptions
            draw_subscriptions
          when :reader
            draw_reader_screen
          end
          handle_input
        end
      end

      # ========== MAIN MENU ==========
      
      def draw_main_menu
        height = TTY::Screen.height
        width = TTY::Screen.width
        
        clear_and_home
        
        write_line @pastel.cyan.bold("Terminal Feedz - Main Menu")
        write_line @pastel.dim("─" * width)
        write_line ""
        
        @menu_items = [
          "Browse Feeds",
          "Manage Categories",
          "Manage Subscriptions",
          "Quit"
        ]
        
        @menu_items.each_with_index do |item, index|
          if index == @selected_index
            write_line @pastel.green("▶ #{item}")
          else
            write_line "  #{item}"
          end
        end
        
        write_line ""
        write_line @pastel.dim("─" * width)
        write_line @pastel.dim("↑↓:navigate Enter:select q:quit")
      end

      # ========== CATEGORY MENU ==========
      
      def draw_category_menu
        height = TTY::Screen.height
        width = TTY::Screen.width
        
        clear_and_home
        
        write_line @pastel.cyan.bold("Manage Categories")
        write_line @pastel.dim("─" * width)
        write_line ""
        
        categories = @config.category_names
        feeds_by_cat = @config.feeds_by_category
        
        @menu_items = []
        categories.each do |cat|
          count = feeds_by_cat[cat]&.length || 0
          @menu_items << { type: :category, name: cat, count: count }
        end
        @menu_items << { type: :action, name: "Add New Category", action: :add }
        @menu_items << { type: :action, name: "Back to Main Menu", action: :back }
        
        visible_height = height - 8
        render_scrollable_list(@menu_items, visible_height) do |item, is_selected|
          case item[:type]
          when :category
            prefix = is_selected ? @pastel.green("▶ ") : "  "
            "#{prefix}#{item[:name]} (#{item[:count]} feeds)"
          when :action
            prefix = is_selected ? @pastel.green("▶ ") : "  "
            "#{prefix}#{item[:name]}"
          end
        end
        
        write_line ""
        write_line @pastel.dim("─" * width)
        if @menu_items[@selected_index][:type] == :category
          write_line @pastel.dim("Enter:view r:rename d:delete Esc:back")
        else
          write_line @pastel.dim("Enter:select Esc:back")
        end
      end

      # ========== FEED LIST ==========
      
      def draw_feed_list
        height = TTY::Screen.height
        width = TTY::Screen.width
        
        clear_and_home
        
        # Header with filters
        category_text = @current_category || "All Categories"
        
        case @read_filter
        when :unread
          status_badge = @pastel.yellow.bold("[UNREAD ONLY]")
        when :read
          status_badge = @pastel.dim.bold("[READ ONLY]")
        else
          status_badge = @pastel.green.bold("[ALL]")
        end
        
        $stdout.write @pastel.cyan.bold("Terminal Feedz - #{category_text} ")
        $stdout.write status_badge
        $stdout.write "\r\n"
        write_line @pastel.dim("─" * width)
        write_line ""
        
        if @feed_manager.feeds_data.empty?
          write_line @pastel.yellow("Loading feeds...")
        elsif @entries.empty?
          write_line @pastel.yellow("No entries match current filters")
          write_line @pastel.dim("Press 'c' to change category or 's' to change status filter")
        else
          visible_height = height - 7
          
          if @selected_index < @scroll_offset
            @scroll_offset = @selected_index
          elsif @selected_index >= @scroll_offset + visible_height
            @scroll_offset = @selected_index - visible_height + 1
          end
          
          visible_entries = @entries[@scroll_offset, visible_height] || []
          visible_entries.each_with_index do |entry, index|
            actual_index = @scroll_offset + index
            is_selected = actual_index == @selected_index
            article_id = @feed_manager.generate_article_id(entry)
            is_read = @config.read?(article_id)
            
            prefix = is_selected ? @pastel.green("▶ ") : "  "
            indicator = is_read ? " " : @pastel.yellow("•")
            title = entry[:title] || "Untitled"
            title = title[0...(width - 30)] + "..." if title.length > width - 30
            
            author = entry[:author] || "Unknown"
            author = author[0...20] + "..." if author.length > 20
            
            date = entry[:published] ? entry[:published].strftime("%m/%d %H:%M") : "No date"
            
            line = "#{prefix}#{indicator} #{title}"
            padding = [0, width - line.length - author.length - date.length - 5].max
            line += " " * padding + @pastel.dim("#{author} · #{date}")
            
            if is_selected
              write_line @pastel.on_bright_black(line)
            else
              write_line line
            end
          end
        end
        
        write_line ""
        footer = "Entries: #{@entries.length} | ↑↓:navigate Enter:read m:mark c:category s:status r:refresh Esc:back"
        write_line @pastel.dim(footer)
      end

      # ========== SUBSCRIPTIONS ==========
      
      def draw_subscriptions
        height = TTY::Screen.height
        width = TTY::Screen.width
        
        clear_and_home
        
        write_line @pastel.cyan.bold("Manage Subscriptions")
        write_line @pastel.dim("─" * width)
        write_line ""
        
        @menu_items = []
        @config.feeds.each do |feed|
          @menu_items << { type: :feed, url: feed['url'], category: feed['category'] }
        end
        @menu_items << { type: :action, name: "Add New Feed", action: :add }
        @menu_items << { type: :action, name: "Back to Main Menu", action: :back }
        
        visible_height = height - 8
        render_scrollable_list(@menu_items, visible_height) do |item, is_selected|
          prefix = is_selected ? @pastel.green("▶ ") : "  "
          case item[:type]
          when :feed
            url_display = item[:url][0...(width - 35)] + (item[:url].length > width - 35 ? "..." : "")
            "#{prefix}#{url_display} #{@pastel.dim("[#{item[:category]}]")}"
          when :action
            "#{prefix}#{item[:name]}"
          end
        end
        
        write_line ""
        write_line @pastel.dim("─" * width)
        if @menu_items[@selected_index][:type] == :feed
          write_line @pastel.dim("Enter:change-category d:delete Esc:back")
        else
          write_line @pastel.dim("Enter:select Esc:back")
        end
      end

      # ========== READER ==========
      
      def draw_reader_screen
        height = TTY::Screen.height
        width = TTY::Screen.width
        
        clear_and_home
        
        entry = @entries[@selected_index]
        return unless entry
        
        title = entry[:title] || "Untitled"
        write_line @pastel.cyan.bold(wrap_text(title, width))
        write_line @pastel.dim("#{entry[:author]} · #{entry[:published]&.strftime("%B %d, %Y %H:%M") || "Unknown date"}")
        write_line @pastel.dim("─" * width)
        write_line ""
        
        visible_height = height - 7
        visible_lines = @content_lines[@reader_scroll, visible_height] || []
        visible_lines.each { |line| write_line line }
        
        $stdout.write "\033[#{height - 1};1H"  # Move to footer position
        write_line @pastel.dim("─" * width)
        scroll_indicator = @content_lines.length > visible_height ? 
          " | Line #{@reader_scroll + 1}/#{@content_lines.length}" : ""
        write_line @pastel.dim("Esc/q:back ↑↓:scroll o:open-url#{scroll_indicator}")
      end

      # ========== INPUT HANDLERS ==========
      
      def handle_input
        key = @reader.read_keypress(nonblock: false)
        
        case @mode
        when :main_menu
          handle_main_menu_input(key)
        when :category_menu
          handle_category_menu_input(key)
        when :feed_list
          handle_feed_list_input(key)
        when :subscriptions
          handle_subscriptions_input(key)
        when :reader
          handle_reader_input(key)
        end
      end

      def handle_main_menu_input(key)
        case key
        when "q", "\u0003"
          cleanup_screen
          exit 0
        when "\e[A", "k"
          @selected_index = [@selected_index - 1, 0].max
        when "\e[B", "j"
          @selected_index = [@selected_index + 1, @menu_items.length - 1].min
        when "\r", "\n"
          case @selected_index
          when 0  # Browse Feeds
            load_feeds_async
            @mode = :feed_list
            @selected_index = 0
            @scroll_offset = 0
          when 1  # Manage Categories
            @mode = :category_menu
            @selected_index = 0
            @scroll_offset = 0
          when 2  # Manage Subscriptions
            @mode = :subscriptions
            @selected_index = 0
            @scroll_offset = 0
          when 3  # Quit
            cleanup_screen
            exit 0
          end
        end
      end

      def handle_category_menu_input(key)
        case key
        when "\e", "\u0003"  # Esc or Ctrl+C
          @mode = :main_menu
          @selected_index = 0
        when "\e[A", "k"
          @selected_index = [@selected_index - 1, 0].max
        when "\e[B", "j"
          @selected_index = [@selected_index + 1, @menu_items.length - 1].min
        when "\r", "\n"
          item = @menu_items[@selected_index]
          case item[:action]
          when :add
            add_category_prompt
          when :back
            @mode = :main_menu
            @selected_index = 0
          else
            @current_category = item[:name]
            load_feeds_async
            @mode = :feed_list
            @selected_index = 0
          end
        when "r"
          item = @menu_items[@selected_index]
          rename_category_prompt(item[:name]) if item[:type] == :category
        when "d"
          item = @menu_items[@selected_index]
          delete_category(item[:name]) if item[:type] == :category
        end
      end

      def handle_feed_list_input(key)
        case key
        when "\e", "\u0003"
          @mode = :main_menu
          @selected_index = 0
          @current_category = nil
        when "\e[A", "k"
          @selected_index = [@selected_index - 1, 0].max
        when "\e[B", "j"
          @selected_index = [@selected_index + 1, @entries.length - 1].min
        when "\e[5~"  # Page up
          @selected_index = [@selected_index - 10, 0].max
        when "\e[6~"  # Page down
          @selected_index = [@selected_index + 10, @entries.length - 1].min
        when "\r", "\n"
          open_reader if @entries[@selected_index]
        when "m"
          toggle_read_status
        when "c"
          cycle_category_filter
        when "s"
          cycle_status_filter
        when "r"
          load_feeds_async
        end
      end

      def handle_subscriptions_input(key)
        case key
        when "\e", "\u0003"
          @mode = :main_menu
          @selected_index = 0
        when "\e[A", "k"
          @selected_index = [@selected_index - 1, 0].max
        when "\e[B", "j"
          @selected_index = [@selected_index + 1, @menu_items.length - 1].min
        when "\r", "\n"
          item = @menu_items[@selected_index]
          case item[:action]
          when :add
            add_feed_prompt
          when :back
            @mode = :main_menu
            @selected_index = 0
          else
            change_feed_category_prompt(item[:url]) if item[:type] == :feed
          end
        when "d"
          item = @menu_items[@selected_index]
          delete_feed(item[:url]) if item[:type] == :feed
        end
      end

      def handle_reader_input(key)
        height = TTY::Screen.height
        visible_height = height - 7
        max_scroll = [@content_lines.length - visible_height, 0].max
        
        case key
        when "q", "\e", "\u0003"
          @mode = :feed_list
          @reader_scroll = 0
        when "o"
          open_in_browser
        when "\e[A", "k"
          @reader_scroll = [@reader_scroll - 1, 0].max
        when "\e[B", "j"
          @reader_scroll = [@reader_scroll + 1, max_scroll].min
        when "\e[5~"
          @reader_scroll = [@reader_scroll - visible_height, 0].max
        when "\e[6~"
          @reader_scroll = [@reader_scroll + visible_height, max_scroll].min
        when "g"
          @reader_scroll = 0
        when "G"
          @reader_scroll = max_scroll
        end
      end

      # ========== HELPER METHODS ==========
      
      def load_feeds_async
        clear_and_home
        write_line @pastel.cyan.bold("Loading feeds...")
        
        @feed_manager.refresh_all
        refresh_entries
      end

      def refresh_entries
        @entries = @feed_manager.all_entries(
          category: @current_category,
          read_status: @read_filter
        )
        @selected_index = [@selected_index, @entries.length - 1].max
        @selected_index = 0 if @selected_index < 0
      end

      def open_reader
        entry = @entries[@selected_index]
        return unless entry
        
        # Mark as read
        article_id = @feed_manager.generate_article_id(entry)
        @config.mark_as_read(article_id)
        
        # Show loading
        clear_and_home
        write_line @pastel.cyan.bold("Loading article...")
        
        @mode = :reader
        @reader_scroll = 0
        @content_lines = fetch_and_format_content(entry)
      end

      def toggle_read_status
        return unless @entries[@selected_index]
        
        entry = @entries[@selected_index]
        article_id = @feed_manager.generate_article_id(entry)
        
        if @config.read?(article_id)
          @config.mark_as_unread(article_id)
        else
          @config.mark_as_read(article_id)
        end
        
        refresh_entries
      end

      def cycle_category_filter
        categories = [nil] + @config.category_names
        current_index = categories.index(@current_category) || 0
        @current_category = categories[(current_index + 1) % categories.length]
        refresh_entries
      end

      def cycle_status_filter
        filters = [:all, :unread, :read]
        current_index = filters.index(@read_filter)
        @read_filter = filters[(current_index + 1) % filters.length]
        refresh_entries
      end

      def add_category_prompt
        print @cursor.show
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        puts @pastel.cyan.bold("Add New Category")
        puts
        print "Category name: "
        name = gets.chomp
        
        if name && !name.empty?
          @config.add_category(name)
          puts @pastel.green("Category added!")
        else
          puts @pastel.red("Cancelled")
        end
        
        sleep 1
        print @cursor.hide
      end

      def rename_category_prompt(old_name)
        return if old_name == 'Uncategorized'
        
        print @cursor.show
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        puts @pastel.cyan.bold("Rename Category: #{old_name}")
        puts
        print "New name: "
        new_name = gets.chomp
        
        if new_name && !new_name.empty?
          @config.rename_category(old_name, new_name)
          puts @pastel.green("Category renamed!")
        else
          puts @pastel.red("Cancelled")
        end
        
        sleep 1
        print @cursor.hide
      end

      def delete_category(name)
        return if name == 'Uncategorized'
        
        print @cursor.show
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        puts @pastel.yellow("Delete category: #{name}?")
        puts @pastel.dim("(Feeds will be moved to Uncategorized)")
        print "Type 'yes' to confirm: "
        confirm = gets.chomp
        
        if confirm == 'yes'
          @config.remove_category(name)
          puts @pastel.green("Category deleted!")
        else
          puts @pastel.red("Cancelled")
        end
        
        sleep 1
        print @cursor.hide
      end

      def add_feed_prompt
        print @cursor.show
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        puts @pastel.cyan.bold("Add New Feed")
        puts
        print "Feed URL: "
        url = gets.chomp
        
        if url && !url.empty?
          print "Category (default: Uncategorized): "
          category = gets.chomp
          category = 'Uncategorized' if category.empty?
          
          @config.add_feed(url, category: category)
          puts @pastel.green("Feed added!")
        else
          puts @pastel.red("Cancelled")
        end
        
        sleep 1
        print @cursor.hide
      end

      def change_feed_category_prompt(url)
        print @cursor.show
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        puts @pastel.cyan.bold("Change Feed Category")
        puts @pastel.dim("Feed: #{url}")
        puts
        puts "Available categories:"
        @config.category_names.each { |cat| puts "  - #{cat}" }
        puts
        print "New category: "
        category = gets.chomp
        
        if category && !category.empty?
          @config.update_feed_category(url, category)
          puts @pastel.green("Category updated!")
        else
          puts @pastel.red("Cancelled")
        end
        
        sleep 1
        print @cursor.hide
      end

      def delete_feed(url)
        print @cursor.show
        print @cursor.clear_screen
        print @cursor.move_to(0, 0)
        puts @pastel.yellow("Delete feed: #{url}?")
        print "Type 'yes' to confirm: "
        confirm = gets.chomp
        
        if confirm == 'yes'
          @config.remove_feed(url)
          puts @pastel.green("Feed deleted!")
        else
          puts @pastel.red("Cancelled")
        end
        
        sleep 1
        print @cursor.hide
      end

      def render_scrollable_list(items, visible_height)
        if @selected_index < @scroll_offset
          @scroll_offset = @selected_index
        elsif @selected_index >= @scroll_offset + visible_height
          @scroll_offset = @selected_index - visible_height + 1
        end
        
        visible_items = items[@scroll_offset, visible_height] || []
        visible_items.each_with_index do |item, index|
          actual_index = @scroll_offset + index
          is_selected = actual_index == @selected_index
          write_line yield(item, is_selected)
        end
      end

      def fetch_and_format_content(entry)
        width = TTY::Screen.width - 4
        
        full_content = fetch_full_article(entry[:url])
        content = full_content || entry[:content] || entry[:summary] || ""
        
        return ["No content available for this article."] if content.empty?
        
        format_content_to_lines(content, width)
      end

      def fetch_full_article(url)
        return nil unless url
        
        begin
          response = HTTP.timeout(15).follow.get(url)
          return nil unless response.status.success?
          
          html = response.body.to_s
          source = Readability::Document.new(html)
          content_html = source.content
          
          # Clean up the HTML before conversion
          content_html = preprocess_html(content_html)
          
          # Convert to markdown
          markdown = ReverseMarkdown.convert(content_html, unknown_tags: :bypass, github_flavored: true)
          markdown
        rescue => e
          nil
        end
      end
      
      def preprocess_html(html)
        return html unless html
        
        doc = Nokogiri::HTML.fragment(html)
        
        # Replace image tags with descriptive placeholders
        doc.css('img').each do |img|
          alt = img['alt'] || img['title'] || 'image'
          src = img['src'] || ''
          replacement = doc.document.create_element('p')
          replacement.content = "[Image: #{alt}]"
          img.replace(replacement)
        end
        
        # Replace video/iframe embeds with placeholders
        doc.css('video, iframe, embed, object').each do |el|
          src = el['src'] || el['data'] || ''
          type = el.name
          replacement = doc.document.create_element('p')
          if src.include?('youtube') || src.include?('youtu.be')
            replacement.content = "[YouTube Video]"
          elsif src.include?('vimeo')
            replacement.content = "[Vimeo Video]"
          elsif src.include?('twitter') || src.include?('x.com')
            replacement.content = "[Twitter/X Embed]"
          else
            replacement.content = "[Embedded #{type.capitalize}]"
          end
          el.replace(replacement)
        end
        
        # Handle figure/figcaption
        doc.css('figcaption').each do |cap|
          cap.content = "Caption: #{cap.text}"
        end
        
        # Add spacing around certain elements
        doc.css('p, div, section, article').each do |el|
          el.add_next_sibling("\n\n") if el.next_sibling
        end
        
        doc.to_html
      end

      def format_content_to_lines(content, width)
        # Decode HTML entities
        decoder = HTMLEntities.new
        content = decoder.decode(content)
        
        # If it's HTML, convert to markdown
        if content.strip.start_with?('<') || content.include?('<p>') || content.include?('<div>')
          begin
            content = preprocess_html(content)
            content = ReverseMarkdown.convert(content, unknown_tags: :bypass, github_flavored: true)
          rescue => e
            content = strip_html(content)
          end
        end
        
        # Clean up excessive whitespace but preserve paragraph breaks
        content = content.gsub(/\n{3,}/, "\n\n")
        content = content.gsub(/[ \t]+/, ' ')
        
        # Render markdown with enhanced formatting
        render_markdown_content(content, width)
      end
      
      def render_markdown_content(content, width)
        lines = []
        in_code_block = false
        code_block_lang = nil
        code_buffer = []
        
        content.split("\n").each do |line|
          # Handle code blocks
          if line.strip.start_with?('```')
            if in_code_block
              # End of code block - render it
              lines.concat(render_code_block(code_buffer.join("\n"), code_block_lang, width))
              lines << ""
              code_buffer = []
              in_code_block = false
              code_block_lang = nil
            else
              # Start of code block
              in_code_block = true
              code_block_lang = line.strip.gsub(/^```/, '').strip
              code_block_lang = nil if code_block_lang.empty?
            end
            next
          end
          
          if in_code_block
            code_buffer << line
            next
          end
          
          # Handle headers
          if line.start_with?('######')
            lines << ""
            lines << @pastel.cyan(line.gsub(/^\#{1,6}\s*/, ''))
            lines << ""
            next
          elsif line.start_with?('#####')
            lines << ""
            lines << @pastel.cyan(line.gsub(/^\#{1,6}\s*/, ''))
            lines << ""
            next
          elsif line.start_with?('####')
            lines << ""
            lines << @pastel.cyan.bold(line.gsub(/^\#{1,6}\s*/, ''))
            lines << ""
            next
          elsif line.start_with?('###')
            lines << ""
            lines << @pastel.yellow.bold(line.gsub(/^\#{1,6}\s*/, ''))
            lines << ""
            next
          elsif line.start_with?('##')
            lines << ""
            lines << @pastel.magenta.bold(line.gsub(/^\#{1,6}\s*/, ''))
            lines << ""
            next
          elsif line.start_with?('#')
            lines << ""
            lines << @pastel.cyan.bold.underline(line.gsub(/^\#{1,6}\s*/, ''))
            lines << ""
            next
          end
          
          # Handle blockquotes
          if line.strip.start_with?('>')
            quote_text = line.gsub(/^[\s>]+/, '')
            wrapped = wrap_text(quote_text, width - 4)
            wrapped.split("\n").each do |wl|
              lines << @pastel.dim("  │ ") + @pastel.italic(wl)
            end
            next
          end
          
          # Handle horizontal rules
          if line.strip.match?(/^[-*_]{3,}$/)
            lines << ""
            lines << @pastel.dim("─" * [width, 40].min)
            lines << ""
            next
          end
          
          # Handle lists
          if line.strip.match?(/^[-*+]\s/)
            list_text = line.gsub(/^(\s*)[-*+]\s/, '\1')
            indent = line.match(/^(\s*)/)[1].length
            wrapped = wrap_text(list_text, width - indent - 4)
            first = true
            wrapped.split("\n").each do |wl|
              if first
                lines << "  " * (indent / 2) + @pastel.green("• ") + format_inline(wl)
                first = false
              else
                lines << "    " + "  " * (indent / 2) + format_inline(wl)
              end
            end
            next
          end
          
          # Handle numbered lists
          if line.strip.match?(/^\d+\.\s/)
            match = line.match(/^(\s*)(\d+)\.\s(.*)/)
            if match
              indent = match[1].length
              num = match[2]
              text = match[3]
              wrapped = wrap_text(text, width - indent - 5)
              first = true
              wrapped.split("\n").each do |wl|
                if first
                  lines << "  " * (indent / 2) + @pastel.green("#{num}. ") + format_inline(wl)
                  first = false
                else
                  lines << "     " + "  " * (indent / 2) + format_inline(wl)
                end
              end
            end
            next
          end
          
          # Handle image placeholders
          if line.include?('[Image:')
            lines << @pastel.dim.italic(line)
            next
          end
          
          # Handle embedded content placeholders
          if line.match?(/\[(YouTube|Vimeo|Twitter|Embedded)/)
            lines << @pastel.blue.italic(line)
            next
          end
          
          # Handle links (standalone on their own line)
          if line.strip.match?(/^\[.+\]\(.+\)$/)
            match = line.match(/\[(.+?)\]\((.+?)\)/)
            if match
              lines << @pastel.blue.underline(match[1]) + @pastel.dim(" (#{match[2]})")
              next
            end
          end
          
          # Regular paragraph text
          if line.strip.empty?
            lines << ""
          else
            wrapped = wrap_text(line.strip, width)
            wrapped.split("\n").each do |wl|
              lines << format_inline(wl)
            end
          end
        end
        
        # If we're still in a code block, render it
        if in_code_block && code_buffer.any?
          lines.concat(render_code_block(code_buffer.join("\n"), code_block_lang, width))
        end
        
        # Clean up multiple blank lines
        cleaned = []
        prev_blank = false
        lines.each do |line|
          if line.strip.empty?
            cleaned << "" unless prev_blank
            prev_blank = true
          else
            cleaned << line
            prev_blank = false
          end
        end
        
        cleaned
      end
      
      def render_code_block(code, lang, width)
        lines = []
        lines << @pastel.dim("┌" + "─" * (width - 2) + "┐")
        
        if lang && !lang.empty?
          lines << @pastel.dim("│ ") + @pastel.yellow(lang.upcase) + @pastel.dim(" │".rjust(width - 4 - lang.length))
          lines << @pastel.dim("├" + "─" * (width - 2) + "┤")
        end
        
        begin
          # Try syntax highlighting with Rouge
          lexer = Rouge::Lexer.find_fancy(lang) || Rouge::Lexers::PlainText.new
          formatter = Rouge::Formatters::Terminal256.new(theme: 'monokai')
          highlighted = formatter.format(lexer.lex(code))
          
          highlighted.split("\n").each do |line|
            # Truncate long lines
            display_line = visible_truncate(line, width - 4)
            lines << @pastel.dim("│ ") + display_line + @pastel.dim(" │".rjust([width - 3 - visible_length(display_line), 1].max))
          end
        rescue => e
          # Fallback to plain code
          code.split("\n").each do |line|
            display_line = line[0, width - 4] || ""
            padding = " " * [width - 4 - display_line.length, 0].max
            lines << @pastel.dim("│ ") + @pastel.white(display_line) + padding + @pastel.dim(" │")
          end
        end
        
        lines << @pastel.dim("└" + "─" * (width - 2) + "┘")
        lines
      end
      
      def format_inline(text)
        # Handle inline code
        text = text.gsub(/`([^`]+)`/) { @pastel.yellow.on_black(" #{$1} ") }
        
        # Handle bold
        text = text.gsub(/\*\*([^*]+)\*\*/) { @pastel.bold($1) }
        text = text.gsub(/__([^_]+)__/) { @pastel.bold($1) }
        
        # Handle italic
        text = text.gsub(/\*([^*]+)\*/) { @pastel.italic($1) }
        text = text.gsub(/_([^_]+)_/) { @pastel.italic($1) }
        
        # Handle strikethrough
        text = text.gsub(/~~([^~]+)~~/) { @pastel.strikethrough($1) }
        
        # Handle inline links
        text = text.gsub(/\[([^\]]+)\]\(([^)]+)\)/) { @pastel.blue.underline($1) }
        
        text
      end
      
      def visible_length(str)
        # Remove ANSI escape sequences to get visible length
        str.gsub(/\e\[[0-9;]*m/, '').length
      end
      
      def visible_truncate(str, max_len)
        return str if visible_length(str) <= max_len
        
        result = ""
        visible = 0
        in_escape = false
        escape_seq = ""
        
        str.each_char do |c|
          if c == "\e"
            in_escape = true
            escape_seq = c
          elsif in_escape
            escape_seq += c
            if c.match?(/[mGKHF]/)
              result += escape_seq
              in_escape = false
              escape_seq = ""
            end
          else
            if visible < max_len
              result += c
              visible += 1
            else
              break
            end
          end
        end
        
        result + "\e[0m"  # Reset at end
      end

      def strip_html(html)
        doc = Nokogiri::HTML.fragment(html)
        text = doc.text
        HTMLEntities.new.decode(text).gsub(/\s+/, ' ').strip
      end

      def wrap_text(text, width)
        return "" if text.nil? || text.empty?
        return text if text.length <= width
        
        words = text.split(/\s+/)
        lines = []
        current_line = ""
        
        words.each do |word|
          if current_line.empty?
            current_line = word
          elsif (current_line + " " + word).length <= width
            current_line += " " + word
          else
            lines << current_line
            current_line = word
          end
        end
        
        lines << current_line unless current_line.empty?
        lines.join("\n")
      end

      def open_in_browser
        entry = @entries[@selected_index]
        return unless entry && entry[:url]
        
        if system("which xdg-open > /dev/null 2>&1")
          system("xdg-open", entry[:url], out: '/dev/null', err: '/dev/null')
        elsif system("which open > /dev/null 2>&1")
          system("open", entry[:url])
        end
      end
    end
  end
end
