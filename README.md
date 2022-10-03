# ruby-gpt3-commander

This is Ruby code for controlling a browser using GPT-3.

### INITIAL SETUP:

Run `bundle install` to install the dependencies.  You'll need Puppeteer (headless Chrome) and that might be  NodeJS thing.

Create a `.env` file and add `OPEN_AI_SECRET_KEY=xxxxxx` where `xxxxxx` is your GPT-3 API key. You'll need the Codex models if you want to run things out of the box.

### HOW THIS WORKS

`run.rb` is a simple terminal application where you can enter your goal, like "what are the most expensive shoes in the world" and the AI will figure out how to use a web browser to get the result on it's own.

`ai_template.rb` implements a very simple way to read parameterized GPT-3 prompts from the file system under `/ai_templates` which contain all the standard GPT-3 params and {{anthing}}, {{you}}, {{want}} as, you guessed it, {{mustache}} variables. The class `AiTemplate` has methods for passing values to your templates to replace those variables and call OpenAi's API for you.

`commander.rb` implements a very narrow set of browser commands -- go click, search and question -- and executes those commands. In most cases, it uses GPT-3 to help form the commands and to execute them -- using simple prompt chaining.

`html_cleaner.rb` is a class to take HTML and simplify it so it's less verbose. This is important because GPT-3 prompts are limited in their size.


### RUNNING THIS

Just run `ruby run.rb` and follow the prompts.

### DISCLAIMERS / ASKS

It would be pretty awesome if someone who understands Puppeteer better than I do would fix and build up those aspects, to add more functionality. It would be pretty powerful to have the AI be able to fill out forms and such.


My personal website: https://currentlyobsessed.com/