# This class contains utilities to simplify HTML for use in size-limited GPT-3 prompts
# without sacrificing the meaning of the HTML.
# Why? Puppeteer surfs and pulls the HTML from pages it visits but the HTML can be quite verbose.
class HtmlCleaner

  BASIC_ELEMENTS = [ "p", "br", "span", "div", "td" ]

  LINKABLES = [
    "a",
    "link",
    "button",
    "btn"
  ]

  SIMPLER_ELEMENT_NAMES = {
    "a" => "link",
    "anchor" => "link",
  }

  CLASS_RENAMER = {
    "title" => "section",
    "btn" => "button",
  }

  # Some common classes that carry meaning (hence GPT-3 processing will care about) and should be preserved.
  CLASS_WHITELIST = [
    "button",
    "btn",
    "link",
    "input",
    "strikethrough",
    "title",
    "rank",
    "priority",
    "star",
    "rating",
    "review",
    "score",
    "price",
    "cost",
    "menu",
    "user",
    "date",
    "time",
    "page",
    "age",
    "month",
    "day",
    "year",
    "type",
    "category",
    "kind",
    "offer",
    "promo",
    "sale",
    "cart",
    "add",
    "image",
    "email",
    "street",
    "city",
    "cities",
    "zip",
    "postal",
    "country",
    "reservation",
    "availability",
    "quantity",
    "inventory",
    "product",
    "sku",
    "notify",
    "share",
    "important",
    "comment",
    "article",
    "venue",
    "location",
    "color",
    "footer",
    "skip",
    "next",
    "previous",
    "cuisine",
    "neighborhood",
  ]

  def self.simpler_element_name(element_name)
    if SIMPLER_ELEMENT_NAMES.key?(element_name.downcase)
      return SIMPLER_ELEMENT_NAMES[element_name.downcase].downcase
    else
      return element_name.downcase
    end
  end

  def self.simpler_class_name(class_name)
    if CLASS_RENAMER.key?(class_name.downcase)
      return CLASS_RENAMER[class_name.downcase].downcase
    else
      return class_name.downcase
    end
  end

  def self.clean_classes(node)
    pclass = node['class']
    keeper_classes = []
    if pclass.present?
      classes = pclass.to_s.split(" ")
      
      # are any of classes (downcased) contained in any of LINKABLES?
      found = classes.select {|class_name| LINKABLES.include?(class_name.downcase)}
      if found.blank?
        # if none of these are LINKABLES, then go up the tree looking for them, and add if found.
        go_up = node.parent
        go_up_classes = go_up['class'].to_s.split(" ")
        while go_up.present?
          go_up_name = go_up.name.downcase
          if LINKABLES.include?(go_up_name)
            if go_up_name == "a"
              go_up_name = "link"
            end
            keeper_classes = [go_up_name] + keeper_classes
            break
          end
          found = go_up_classes.select {|class_name| LINKABLES.include?(class_name.downcase)}
          if found.present?
            found.each do |found_class|
              if found_class == "a"
                found_class = "link"
              end
              keeper_classes = [found_class] + keeper_classes
            end
            break
          end
          if node.parent == go_up
            break
          end
          go_up = node.parent
        end
      end

      # only keep classes if they contain (as a substring) any of the words in the CLASS_WHITELIST
      # and only keep the whitelist verion of the class (which is simpler / more compact semantics)
      search_classes = CLASS_WHITELIST.dup
      classes.each do |class_name|
        search_classes.each do |wl_class|
          if class_name.downcase.include?(wl_class.downcase)
            keeper_classes << simpler_class_name(wl_class.downcase)
            search_classes.delete(wl_class)
          end
        end
      end
      keeper_classes.uniq!
    end

    return keeper_classes
  end

  def self.clean_html(raw_html, page_title: nil, page_url: nil)
    html = raw_html.encode('UTF-8', invalid: :replace, undef: :replace, replace: '', universal_newline: false).gsub(/\P{ASCII}/, '')
    parser = Nokogiri::HTML(html, nil, Encoding::UTF_8.to_s)
    parser.xpath('//script')&.remove
    parser.xpath('//style')&.remove

    # Build the new doc as we go.
    nodes_processed = []

    # parse the HTML into nodes
    # and build into a tree of depth=2 where parents have children
    # and the parents are in order.
    # First, get all the leaf nodes in order.
    leaf_nodes = []
    parser.xpath('//*[not(*)]').each do |node|
      leaf_nodes << node
    end

    # Next, go through getting parents (in order) and build a data structure
    # that will store the 1:n relation of parent to child/leaf.
    parent_hashses = []
    leaf_nodes.each do |node|
      parent = node.parent
      if parent.present?
        # Find that parent in the parent_hashses
        parent_index = parent_hashses.index { |h| h[:parent] == parent }
        if parent_index.present?
          # add this child to the parent array
          parent_hashses[parent_index][:children] << node
        else
          # create a new parent hash
          parent_hashses << { parent: parent, children: [node] }
        end
      end
    end

    # Finally, go through and BUILD HTML:
    build_html = []
    parent_hashses.each do |parent_hash|
      parent = parent_hash[:parent]
      children = parent_hash[:children]
      formatted = format_parent_and_chilren(parent, children)
      if formatted.present?
        build_html << formatted
      end
    end

    # Add a metatag at the top of the URL
    if page_title.present? && page_url.present?
      build_html.unshift("<meta name='og:title' content='#{page_title}' />")
      build_html.unshift("<meta name='og:url' content='#{page_url}' />")
    end

    # Print a few lines of the HTML for debugging purposes:
    debug = false
    if debug
      puts " - - - - - - - - - ".white.bold
      build_html.first(50).each do |line|
        puts "     " + line.white
      end
      puts " - - - - - - - - - ".white.bold
      puts ""
    end

    # Return a complete list of all classes in the original HTML
    #  and the new HTML.
    original_classes = []
    parser.xpath('//*').each do |node|
      if node.attributes["class"].present?
        class_string = node.attributes["class"].value
        class_string.split(" ").each do |c|
          original_classes << c
        end
      end
    end

    build_html.join("\n")
  end

  def self.format_parent_and_chilren(parent, children)
    node_html = ""
    if children.count > 1
      keeper_classes = clean_classes(parent)
      # Remove any classes that are equal to the element name.
      #  <link class='link'>Top Rated</link> --> <link>Top Rated</link>
      keeper_classes = keeper_classes.reject { |c| c.downcase == parent.name.downcase }

      parent_name = simpler_element_name(parent.name)
      needs_parent = true

      if keeper_classes.blank?
        if parent_name == "p" || parent_name == "br" || parent_name == "div" || parent_name == "span"
          needs_parent = false
        else
          node_html << "<#{parent_name}>"
        end
      else
        node_html << "<#{parent_name} class='#{keeper_classes.join(' ')}'>"
      end

      children_html = ""
      children.each do |child|
        child_html = format_child_node(child)
        if child_html.present?
          child_html = "\n  " + child_html
          children_html << child_html
        end
      end
      if children_html.blank?
        return ""
      else
        node_html << " #{children_html}"
      end
      if needs_parent
        node_html << "\n</#{parent_name}>"
      end
    else
      child_html = format_child_node(children.first)
      if child_html.present?
        node_html << child_html
      end
    end
    node_html
  end

  # Take a single parsed HTML node and reformat to something simpler.
  def self.format_child_node(node)
    element = simpler_element_name(node.name).downcase
    # get the immedate text in the node (not children)
    text = node.content.strip

    # if the text parent has signifiant classes, put them in as they may be hints as to the meaning.
    keeper_classes = clean_classes(node)

    # Is this needed?
    if keeper_classes.present? && element.blank?
      element = "p"
    end

    # If the element is p, br, div or span, "elevate" the first class name to be the element name.
    # Examples:
    #   <p class='score'>228 points</p> --> <score>228 points</score>
    #   <div class='button time'>6:00PM</div> --> <button class='time'>6:00PM</button>

    if keeper_classes.present?
      if BASIC_ELEMENTS.include?(element)
        element = keeper_classes[0]
        keeper_classes.shift # removes the first element
      end
    end

    # Remove any classes that are equal to the element name.
    #  <link class='link'>Top Rated</link> --> <link>Top Rated</link>
    keeper_classes = keeper_classes.reject { |c| c.downcase == element.downcase }

    text = text.strip
    # if the text only contains ascii chars 32 and 160, then it's just whitespace.
    if text.gsub(/[\s\u00A0]/, '').empty?
      text = ""
    end

    formatted = ""

    if text.blank?
      return ""
    end

    # If the element is H1, H2, H3, H4, H5, H6, then we don't need the class "section"
    hs = ["h1", "h2", "h3", "h4", "h5", "h6"]
    if hs.include?(element)
      keeper_classes.delete("section")
    end

    # If the element has no classes and is span | p | br | div | td, then just return the text.
    if keeper_classes.blank? && BASIC_ELEMENTS.include?(element)
      return text
    end

    # If the element has no classes and the parent has multiple children, then just return the text.
    #if keeper_classes.blank? && node.parent.children.count > 1
    #  return text
    #end

    if element.present?
      keeper_classes_str = keeper_classes.join(' ')
      href = ""
      # if the node has href, add it back in to formatted.
      if node.attributes["href"].present?
        href = node.attributes["href"].value
        href = " href='#{href}'"
      end
      
      if keeper_classes_str.present?
        formatted = "<#{element} class='#{keeper_classes_str}'#{href}>#{text}</#{element}>"
      else
        formatted = "<#{element}#{href}>#{text}</#{element}>"
      end
    else
      formatted = text
    end
  
    return formatted
  end


  # if HTML is too large to put into the parameter in a prompt,
  # we split it so we can run the prompt multiple times and post-process
  # the results.
  def self.split_for_open_ai(clean_html, prompt, overhead)
    open_ai_max_tokens = 2048
    open_ai_max_chars = (open_ai_max_tokens * 4).to_i
    safe_buffer = 100
    max_chars = open_ai_max_chars - overhead.length - prompt.length - safe_buffer
    split_html(clean_html, max: max_chars)
  end

  # Split the HTML into several arrays where the length of each string
  # is less than max, and do not split inside of tags.
  # OpenAI: or most models this is 2048 tokens, or about 1500 words
  # One token is ~4 characters of text for common English text
  def self.split_html(clean_html, max: 3900)

    if clean_html.length <= max
      return [clean_html]
    end

    # use regex to split by closing tags
    # keep the closing tag in results.
    # instead of clean_html.split(/<\/[^>]+>/), use: ?= operator
    groups = clean_html.split(/(?=<\/[^>]+>)/)

    ar_parts = []
    cur_part_len = 0
    next_chunk = []
    groups.each do |bits, i|
      cur_part_len = cur_part_len + bits.length
      if cur_part_len < max
        next_chunk << bits
      else
        ar_parts << next_chunk
        next_chunk = []
        next_chunk << bits
        cur_part_len = bits.length
      end
    end

    if !ar_parts.include?(next_chunk)
      ar_parts << next_chunk
    end

    # Join all the parts
    parts = []
    ar_parts.each do |sub_array|
      parts << sub_array.join(" ")
    end  

    # Pull out the meta name='og:url' and meta name='og:title' tags.
    parsed = Nokogiri::HTML(clean_html)
    og_url = parsed.css("meta[name='og:url']").first.try(:attr, "content")
    og_title = parsed.css("meta[name='og:title']").first.try(:attr, "content")

    # Add a meta page "page 1 of 2" to each part.
    # And the og:url and og:title to pages 2+
    total_parts = parts.length
    parts = parts.map.with_index do |part, i|
      if i >= 1
        part = "<meta name=\"og:url\" content=\"#{og_url}\">\n" + part
        part = "<meta name=\"og:title\" content=\"#{og_title}\">\n" + part
      end
      part = "<meta name=\"page\" content=\"#{i+1} of #{total_parts}\">\n" + part 
    end

    parts
  end
end