# A class that handles interfacing with Pupeteer
# to control a browser session.
require_relative 'html_cleaner'
require 'nokogiri'
require 'rmagick'
require 'securerandom'
require 'similar_text'
require 'tempfile'

class Commander
  DEFAULT_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 14_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Mobile/15E148 Safari/604.1"

  def self.page_command_search(page, text)
    text = text.strip
    text = text.gsub(/[\s\u00A0]/, ' ')

    # Special case: youtube
    if page.url.include?("youtube.com")
      uri_escaped = URI.escape(text)
      page.wait_for_navigation do
        page.goto("https://www.youtube.com/results?search_query=#{uri_escaped}", wait_until: "networkidle0")
      end
      return
    end

    # type "joe" in the text field.
    # Look for the form
    form = page.query_selector("form")
    if form.nil?
      text_field = page.query_selector("input[type=text]") || page.query_selector("input[type=search]")
    else
      text_field = form.query_selector("input[type=text]") || form.query_selector("input[type=search]")
    end

    if text_field.nil?
      puts "No text field found".red
      return
    end

    text_field.scroll_into_view_if_needed

    # Set the value to nothing.
    text_field.evaluate("b => b.value = ''")

    # type backspace to clear it
    text_field.type_text("\b")

    # type the new search
    page.keyboard.type_text(text)

    # wait for it to load
    page.wait_for_function('() => document.querySelector("*") !== null', timeout: 0) do
    end

    # type enter and let it navigate.
    page.keyboard.press("Enter")

    page.wait_for_function('() => document.querySelector("*") !== null', timeout: 0) do
    end

    sleep(1)
  end

  def self.click_link(page, link)
    url = link.evaluate("e => e.href")
    link_anchor_text = link.evaluate("e => e.innerText")
    page.goto(url, wait_until: "load", timeout: 0)
    page.wait_for_function('() => document.querySelector("*") !== null', timeout: 0) do
    end
    sleep(2)
  end

  # Ask the AI for the best URL to click given some HTML and some text with meaning.
  # last_history_text stores some context that might be helpful to the AI.
  # return {anchor:, url:} hash
  def self.page_command_smart_click(page, text, last_history_text)
    # Ask the AI to find the best link on the page for the given intent.
    html = page.content
    link_hash = Commander.determine_best_link_url(html, text, last_history_text)
    if link_hash.present?
      # Find the link in the page.
      link = page.query_selector("a[href='#{link_hash["url"]}']")
      if link.present?
        Commander.click_link(page, link)
      else
        Commander.page_command_navigate_to(page, link_hash[:url])
      end
      return link_hash
    else
      puts "No link found for: #{text}".red
    end    
  end

  def self.page_command_navigate_to(page, url)
    page.wait_for_navigation do
      page.goto(url, wait_until: "networkidle0")
    end
  end

  # Return the text of the best link match as a hash {anchor:, url:}
  def self.determine_best_link_url(html, description, last_history_text)
    clean_html = HtmlCleaner.clean_html(html)
    ai_template = AiTemplate.load(token: "determine_best_link_url")
    parts = HtmlCleaner.split_for_open_ai(clean_html, ai_template.prompt, description)

    # For now, just pulling as much HTML as I can actually feed to a prompt.
    # Another approach could be to run each html chunk and then use more AI
    # to determine the best one.
    part = parts.first
    params = {
      "html" => part,
      "description" => description,
      "history" => last_history_text
    }
    json_string = ai_template.run(
      params: params
    )
    return JSON.parse(json_string.strip)
  end

  def self.overall_best_answer(question, answers)
    AiTemplate.run!(
      token: "overall_best_answer", 
      params: {
        "question" => question,
        "answers" => answers.join("\n")
      }
    )
  end

  def self.page_command_question(clean_html, question, last_history_text)
    ai_template = AiTemplate.load(token: "page_command_question")
    # Since we can't put too many things into the OPENAI we split up the page content.
    #
    # OpenAI: or most models this is 2048 tokens, or about 1500 words
    # One token is ~4 characters of text for common English text

    parts = HtmlCleaner.split_for_open_ai(clean_html, ai_template.prompt, question)

    answers = []
    # Total Hack: only do the first 2
    parts.first(2).each do |part_page_content|
      results = ai_template.run(
        params: {
          "page_content" => part_page_content,
          "question" => question
        }
      )  
      answers << results        
    end

    # find overall best answer
    Commander.overall_best_answer(question, answers)
  end

  # Given a pupeteer's browser page, run the command.
  # Might return a string result, depending on the command type.
  def self.run_command_on_page(page:, command:, history:)
    result = ""
    raw_html = page.content
    clean_html = HtmlCleaner.clean_html(raw_html, page_title: page.title, page_url: page.url)      

    # Each command is a word ending in ":" with arguments that follow.
    if command.include?(":")
      # The action is everything before the first ":"
      action = command.split(":")[0].strip

      # The args is everything after the first ":"
      index = command.index(":")
      args = command[index+1..-1].strip
    else
      action = command.split(" ").first
      # remove the first occurrence of action from the command
      args = command.split(" ").drop(1).join(" ")
    end

    if action.blank?
      puts "command: [#{command}]".red.bold
      raise ("Command lacks action: #{command}")
    end

    action_downcase = action.downcase

    # Pull the last command from history and format it for the AI
    history_formatted = []
    last_history = history.try(:last)
    if last_history.present?
      history_formatted << "# last command: #{last_history[:command]}"
      history_formatted << "# last result: #{last_history[:result]}"
    end
    last_history_text = history_formatted.join("\n")
    
    case action_downcase
    when "go"
      # args is a URL.
      args = "https://#{args}" if !args.start_with?("http")
      Commander.page_command_navigate_to(page, args)
      result = "Opened #{args}"
    when "click"
      # args is a string to click
      link_hash = Commander.page_command_smart_click(page, args, last_history_text)
      if link_hash.present?
        if args != link_hash['anchor']
          info = "Clicked \"#{args}\" -> #{link_hash['anchor']}"
        else
          info = "Clicked \"#{args}\""
        end
        domain = URI.parse(link_hash['url']).host
        if domain.present?
          info += " (#{domain})"
        end
        result = info
      else
        info = "Could not click \"#{args}\""
        result = info
      end
    when "search"
      Commander.page_command_search(page, args)
      info = "Searched for \"#{args}\""
      result = info
    when "question"
      answer = Commander.page_command_question(clean_html, args, last_history_text)
      result = "Q: #{args}, A: #{answer}"
    else
      # Unknown command
      result = "Unknown command! action: #{action}, args: #{args}"
    end
    return result
  end
end