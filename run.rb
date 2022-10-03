# a ruby class to execute a simple terminal driven UI for the commander app
# (AI driven browser control)

require_relative "ai_template"
require_relative "commander"
require "active_support/all"
require "awesome_print"
require "colorize"
require "dotenv"
require "httparty"
require "puppeteer-ruby"
require "tty-box"
require "tty-font"
require "tty-screen"

Dotenv.load

# Load all the templates in the ai_templates folder
# and validate that their formatting looks good.
def validate_templates!
  # Templates are stored in the ai_templates folder as {token}.txt files.
  # Iterate through files in that directory:
  errors = []
  Dir.foreach("ai_templates") do |filename|
    next if filename == "." || filename == ".."
    next if !filename.end_with?(".txt")
    # load the template and validate it:
    token = filename.split(".")[0]
    begin
      ai_template = AiTemplate.load(token: token)
      ai_template.validate!
    rescue => e
      errors << "Template #{token}.txt: #{e.message}"
    end
  end
  if errors.any?
    raise errors.join("\n")
  end
end

# throw an exception if the .env doesn't include
# required environment variables.
def validate_env!
  required_env_vars = %w(OPEN_AI_SECRET_KEY)
  missings = []

  # if the .env file is missing, tell them so.
  if !File.exist?(".env")
    raise "Error: missing .env file. Please create a .env file and fill in the values for #{required_env_vars.join(', ')}."
  end

  required_env_vars.each do |var|
    if ENV[var].nil?
      missings << var
    end
  end
  if missings.any?
    raise "Error: missing required environment variables: #{missings.join(', ')}"
  end
end

def print_instructions
  lines = []
  font = TTY::Font.new(:standard)
  title = font.write("Commander")
  # Colorize each line
  big_title = title.split("\n").map { |line| line.green.bold }.join("\n")

  lines << big_title
  lines << "This is a simple terminal driven UI for the Commander app."
  lines << "Commander is an AI driven browser control app."
  lines << "It uses OpenAI's GPT-3 API to generate commands for the browser."
  lines << "You can use it to automate tasks in your browser."
  lines << ""
  lines << "Instructions: Enter something.".white.bold
  puts TTY::Box.frame(lines.join("\n"), padding: 2, width: TTY::Screen.width)
end

def print_summary_of_session(human_entries:, history:)
  history_formatted_lines = []
  history.each_with_index do |h, i|
    history_formatted_lines << "Command #{i+1}: #{h[:command]}"
    history_formatted_lines << "Result #{i+1}: #{h[:result]}"
    history_formatted_lines << ""
  end
  history_formatted = history_formatted_lines.join("\n")

  template = AiTemplate.load(token: "summarize_session")
  params = {
    human_entries: human_entries.join("\n"),
    history: history_formatted
  }

  res = template.run(
    params: params
  )
  puts "=============================".red.bold
  puts template.replace_params(params: params)

  summary_lines = []
  summary_lines << "Original goal:".white.bold
  summary_lines << human_entries.join("\n").yellow
  summary_lines << ""
  summary_lines << "Summary:".white.bold
  summary_lines << res.green.bold
  summary_lines << ""
  summary_lines << "Raw AI steps taken:".white.bold
  summary_lines << history_formatted.yellow
  

  # Big title font
  font = TTY::Font.new(:standard)
  title = font.write("Summary of Session")
  # Colorize each line
  big_title = title.split("\n").map { |line| line.white.bold }.join("\n")

  puts TTY::Box.frame(big_title, summary_lines.join("\n"), padding: 1, width: TTY::Screen.width)
end

def ask(terminal_prompt, guide)
  print terminal_prompt.white.bold + " <#{guide}> ".white
  gets.chomp
end

begin
  validate_env!
  validate_templates!
rescue => e
  puts TTY::Box.frame("Errors:", e, padding: 1, width: TTY::Screen.width)
  exit 1
end

print_instructions

# remember everything humans enter as we go.
human_entries = []
cmd = ask("What do you want to do?", "enter a goal")
human_entries << cmd if cmd.present?

# The puppeteer session. Note that headless: false means that the browser will be visible.
Puppeteer.launch(headless: false) do |browser|
  page = browser.new_page
  page.viewport = Puppeteer::Viewport.new(width: 800, height: 1200, device_scale_factor: 1.0)
  page.set_user_agent(Commander::DEFAULT_USER_AGENT)

  if cmd.blank?
    puts "using default command".white.bold
    cmd = "what is the best omakase sushi experience in NYC?"
    human_entries << cmd
  end

  # start a loop to process commands and then ask for more commands
  history = []

# The AI instructions_to_commands translates each line of our human instructions into a 
  # simple, machine-readable commands that our engine can understand.
  res = AiTemplate.run!(token: "instructions_to_commands", params: {input: cmd})
  cmd_list = res.split("\n")

  lines = []
  lines << "GIVEN:".white.bold
  lines << cmd.yellow
  lines << "PERFORM:".white.bold
  lines << res.yellow
  puts TTY::Box.frame(lines.join("\n"), e, padding: 1, width: TTY::Screen.width)

  # Here's where we run the command.
  # Sometimes it's helpful to give GPT-3 prompts some context such as the last command and results
  # In case that helps the AI figure out what to do for the current command. Thus, we pipe those in. 
  cmd_list.each do |command|
    result = Commander.run_command_on_page(page: page, command: command, history: history)
    lines  = []
    lines << "COMMAND: ".yellow.bold + " " + command.yellow
    lines << "RESULT: ".white.bold + " " + result.white
    history << {
      command: command,
      result: result
    }
    puts TTY::Box.frame(lines.join("\n"), e, padding: 1, width: TTY::Screen.width)
  end

  print_summary_of_session(human_entries: human_entries, history: history)

end
