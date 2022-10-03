# This class represents a GPT-3 prompt but with simple {{slugs}}
# so that one can easily replace them with the appropriate values
# at runtime.  This allows for useful prompt reuse with dynamic inputs.
#
# This class also handles calling into GPT-3 and to get the results
# and fetching the AI Template data from flat files (in the /ai_templates dir)

class AiTemplate
  # Each AI Template has a few attributes:
  # - name: the name of the template.
  # - token: a unique short identifier for the template which is also the file name and key.
  # - description: a short description of the template for humans.
  # - temperature: the GPT-3 temperature to use for this prompt.
  # - engine: the GPT-3 engine to use for this prompt.
  # - n: the GPT-3 number of result to return for this prompt.
  # - top_p: the GPT-3 top_p to use for this prompt.
  # - frequency_penalty: the GPT-3 frequency_penalty to use for this prompt.
  # - presence_penalty: the GPT-3 presence_penalty to use for this prompt.
  # - stop_strs: stop strings separated by "~".
  #
  # Create those attributes:
  attr_accessor :name, :token, :description, :temperature, :engine, :n, :top_p, :frequency_penalty, :presence_penalty, :max_tokens, :stop_strs, :prompt
  
  def self.run!(token:, params:)
    AiTemplate.load(token: token).run(params: params)
  end

  # Run the template with the provided parameters
  def run(params:)
    prompt_replaced = replace_params(params: params)

    # call into GPT-3
    open_ai_gtp3_url = "https://api.openai.com/v1/engines/#{self.engine}/completions"

    stop_strs_array = nil
    stop_strs_array = self.stop_strs.split("~").map {|s| s.gsub("\\n", "\n")} if self.stop_strs.present?

    open_ai_params = {
      prompt: prompt_replaced.strip,
      temperature: self.temperature.to_f,
      stop: stop_strs_array,
      top_p: self.top_p.to_f,
      n: self.n.to_i,
      stream: false,
      presence_penalty: self.presence_penalty.to_f,
      frequency_penalty: self.frequency_penalty.to_f,
      max_tokens: self.max_tokens.to_i
    }

    request_headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{ENV['OPEN_AI_SECRET_KEY']}"
    }

    # avoid "You didn't provide an API key. You need to provide your API key in an Authorization header using Bearer auth (i.e. Authorization: Bearer YOUR_KEY)"
    if ENV['OPEN_AI_SECRET_KEY'].nil?
      puts "You need to set the OPEN_AI_SECRET_KEY environment variable in .env to your OpenAI API key."
      exit 1
    end

    response = HTTParty.post(
      open_ai_gtp3_url,
      :body => JSON.dump(open_ai_params),
      :headers => request_headers,
      timeout: 60
    )

    hash = JSON.parse(response.body)

    # return the first result, stripped for convenience.
    hash["choices"][0]["text"].strip if hash["choices"].present? && hash["choices"][0].present?
  end

  # Given our templates may be parameterized with {{variables}}
  # this method will find them and replace them with the provided values.
  def replace_params(params:)
    ready_prompt = self.prompt
    params.each do |key, value|
      ready_prompt = ready_prompt.gsub("{{#{key}}}", value)
    end

    # error if any unreplaced {{variables}} remain.
    # search for {{ + text + }}
    if ready_prompt =~ /{{.*}}/
      which_remain = ready_prompt.scan(/{{.*}}/)
      raise "Error: required prompt variables missing: #{which_remain.join(', ')}"
    end

    return ready_prompt
  end


  # Parse a template file.
  # Todo: error handling, smart defaults, etc.
  def self.parse_param(line:, param_name:, ai_template:)
    if line && line.start_with?("#{param_name}:")
      val = line.split(":")[1].to_s.strip
      # set the attribute on the ai_template object:
      ai_template.send("#{param_name}=", val)
    end
  end

  # look for the template.txt in the ai_templates folder with the name token
  # and load the object.
  # The file format is:
  #  -- one or more lines of names params corresponding to GPT-3 prompt parameters.
  #  -- a blank line
  #  -- the rest of the file is the prompt text with {{slug}} variables for dynamic values.
  #
  def self.load(token:)
    if token.nil?
      raise "No token provided"
    end
    if !File.exist?("ai_templates/#{token}.txt")
      raise "No template found for token #{token}"
    end
    text = File.read("ai_templates/#{token}.txt")

    # parse the file looking lines starting with the known attribute names + ":" and store the values
    lines = text.split("\n")
    ai_template = AiTemplate.new
    ai_template.token = token
    lines.each do |line|
      parse_param(line: line, param_name: "name", ai_template: ai_template)
      parse_param(line: line, param_name: "token", ai_template: ai_template)
      parse_param(line: line, param_name: "max_tokens", ai_template: ai_template)
      parse_param(line: line, param_name: "description", ai_template: ai_template)
      parse_param(line: line, param_name: "temperature", ai_template: ai_template)
      parse_param(line: line, param_name: "engine", ai_template: ai_template)
      parse_param(line: line, param_name: "n", ai_template: ai_template)
      parse_param(line: line, param_name: "top_p", ai_template: ai_template)
      parse_param(line: line, param_name: "frequency_penalty", ai_template: ai_template)
      parse_param(line: line, param_name: "presence_penalty", ai_template: ai_template)
      parse_param(line: line, param_name: "stop_strs", ai_template: ai_template)      
    end

    # parse everything after the first blank line into prompt:
    blank_line_index = lines.index("")
    ai_template.prompt = lines[blank_line_index..lines.length].join("\n").strip

    return ai_template
  end

  # Quick validation of a template file.
  # This will help if people try making their own template files.
  def validate!
    raise "missing a name" if self.name.nil?
    raise "missing a description" if self.description.nil?
    raise "missing a temperature" if self.temperature.nil?
    raise "missing an engine" if self.engine.nil?
    raise "missing an n" if self.n.nil?
    raise "missing a top_p" if self.top_p.nil?
    raise "missing a frequency_penalty" if self.frequency_penalty.nil?
    raise "missing a presence_penalty" if self.presence_penalty.nil?
    raise "missing a stop_strs" if self.stop_strs.nil?
  end

end