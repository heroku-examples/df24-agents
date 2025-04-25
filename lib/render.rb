class Render
  attr_reader :all_responses

  DEBUG_LOG_FILE = "mia_debug.log".freeze

  def initialize
    @pastel = Pastel.new.magenta.bold.detach
    @prompt = TTY::Prompt.new
    @client = OpenAI::Client.new(
      access_token: ENV["INFERENCE_KEY"],
      uri_base: ENV["INFERENCE_URL"]
    )
    @all_responses = [] # keeps a record of the responses that stream back
    @debug_logging_enabled = true
    @debug_log = File.open(DEBUG_LOG_FILE, "a") if @debug_logging_enabled
    _log_debug("\n\n=== NEW RENDER INSTANCE INITIALIZED #{Time.now} ===")
  end

  def heroku_print(str)
    puts @pastel.call(str)
  end

  def print_markdown(md)
    markdown = <<~MARKDOWN

    #{md}

    MARKDOWN

    unless ENV["DARK_MODE"] == "true"
      Rouge::Themes.send(:remove_const, :ThankfulEyes)
      Rouge::Themes.const_set(:ThankfulEyes, Rouge::Themes::Github)
    end

    puts TTY::Markdown.parse(markdown)
  end

  def print_info(str)
    puts TTY::Box.info(str)
  end

  def print_ok(str)
    puts TTY::Box.success(str)
  end

  def print_warn(str)
    puts TTY::Box.warn(str)
  end

  def print_error(str)
    puts TTY::Box.error(str)
  end

  def select(question:, opts:)
    @prompt.select(question, opts)
  end

  def hr
    markdown_string = "\n\n***\n\n"
    puts TTY::Markdown.parse(markdown_string)
  end

  def print_box(str)
    style = {
      border: {
        fg: :blue
      }
    }

    box = TTY::Box.frame(width: 80, height: 15, align: :left, style:) do
      str
    end
    puts "\n#{box}"
  end

  def print_large_box(str)
    style = {
      border: {
        fg: :blue
      }
    }

    box = TTY::Box.frame(width: 80, height: 40, align: :left, style:) do
      str
    end
    puts "\n#{box}"
  end

  def inference_request(request:, print_last_message: true)
    request = JSON.parse(request)
    spinner = nil

    _log_debug("Starting inference request with params: #{request.reject { |k, _| k == 'messages' }.inspect}")
    _log_debug("Request messages: #{request['messages'].inspect}") if request['messages']

    with_spinners("MIA is thinking...") do |spinners|
      spinner = spinners.register(
        "Sending an inference request to Heroku... :spinner",
        success_mark: "✅"
      )
      spinner.auto_spin

      stream_proc = Proc.new do |chunk, _bytesize|
        spinner.success if spinner
        @all_responses << chunk
        _log_debug("Received response chunk: #{chunk.inspect}")
        spinner = spinners.register(
          "#{summarize_message(chunk.dig("choices", 0, "message"))}... :spinner",
          success_mark: "✅"
        )
        spinner.auto_spin
      end

      begin
        @client.chat(parameters: request.merge(stream: stream_proc))
      rescue => e
        _log_debug("Error in inference request: #{e.class} - #{e.message}")
        _log_debug(e.backtrace.join("\n")) if e.backtrace
        raise e
      end
    end

    # Mark the last spinner as complete
    spinner.success

    if @all_responses.empty?
      _log_debug("Warning: No responses received from inference request")
    else
      _log_debug("Completed inference request successfully")
    end

    # Print the content of the last response
    if print_last_message
      print_box(@all_responses.last.dig("choices", 0, "message", "content"))

      # Display tool call results if present
      display_tool_results(@all_responses)
    end

    @all_responses.last # Return the last response
  end

  # Display results from tool calls, particularly database related ones
  def display_tool_results(responses)
    # Track tool calls and responses
    query_results = []

    # Print summary of tool chain
    heroku_print("\nTool Execution Summary:")

    responses.each_with_index do |response, index|
      message = response.dig("choices", 0, "message")
      next unless message

      # Check if this message contains tool calls
      if message["tool_calls"]
        message["tool_calls"].each do |tool_call|
          function = tool_call.dig("function")
          next unless function

          tool_name = function["name"]
          begin
            args = JSON.parse(function["arguments"])

            case tool_name
            when "database_get_schema"
              heroku_print("\n🔍 Database Schema Requested")
            when "database_run_query"
              if args["query"]
                heroku_print("\n📊 Database Query Executed:")
                print_markdown("```sql\n#{args["query"]}\n```")
                query_results << args["query"]
              end
            end
          rescue JSON::ParserError => e
            _log_debug("Error parsing tool call arguments: #{e.message}")
          end
        end
      end
    end
  end

  def with_spinners(action_msg, &block)
    puts "\n"
    _log_debug("Starting spinner action: #{action_msg}")
    spinners = TTY::Spinner::Multi.new(
      @pastel.call("#{action_msg}... :spinner"),
      format: :dots_2
    )
    begin
      yield(spinners)
      _log_debug("Spinner action completed: #{action_msg}")
    rescue => e
      _log_debug("Error in spinner action '#{action_msg}': #{e.class} - #{e.message}")
      _log_debug(e.backtrace.join("\n")) if e.backtrace
      raise e
    end
  end

  def confirm(msg)
    @prompt.yes?(msg)
  end

  private

  def summarize_message(message)
    return "No message to summarize" if message.nil?
    _log_debug("Summarizing message with role: #{message["role"]}")

    case message["role"]
    when "user"
      "Prompt sent."
    when "assistant"
      tool_call = message.dig("tool_calls", 0)
      if tool_call
        args = JSON.parse(tool_call.dig("function", "arguments"))
        tool_name = tool_call.dig("function", "name")
        _log_debug("Tool call detected: #{tool_name} with args: #{args.inspect}")

        case tool_name
        when /\Aweb_browsing_single_page/, /\Aweb_browsing_multi_page/
          "MIA is reading the page #{args["url"]} ..."
        when /\Acode_exec_ruby/
          "Executing Ruby code..."
        when /\Acode_exec_python/
          "Executing Python code..."
        when /\Acode_exec_node/
          "Executing Node.js code..."
        when /\Acode_exec_go/
          "Compiling and executing Go code..."
        when /\Adatabase_get_schema/
          "MIA is reading the database's schema..."
        when /\Adatabase_run_query/
          "Querying the database..."
        when /\Adyno_run_command/
          "Running the command on the Heroku dyno..."
        when "create_pie_chart"
          "MIA is requesting a local tool..."
        when /\Asearch_web/
          "Searching the web for #{args["search_query"]} ..."
        when /\Apdf_read/
          "Reading the PDF at #{args["url"]} ..."
        end
      else
        _log_debug("No tool calls in assistant message")
        "MIA has the information it needs."
      end
    end
  end

  def _log_debug(message)
    return unless @debug_logging_enabled && @debug_log
    timestamp = Time.now.strftime("%Y-%m-%d %H:%M:%S.%L")
    @debug_log.puts("[#{timestamp}] #{message}")
    @debug_log.flush # Ensure messages are written immediately
  end
end
