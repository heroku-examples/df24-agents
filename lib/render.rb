class Render
  def initialize
    @pastel = Pastel.new.magenta.bold.detach
    @prompt = TTY::Prompt.new
    @client = OpenAI::Client.new(
      access_token: ENV["DYNO_INTEROP_TOKEN"],
      uri_base: ENV["DYNO_INTEROP_BASE_URL"]
    )
  end

  def heroku_print(str)
    puts @pastel.call(str)
  end

  def print_markdown(md)
    puts TTY::Markdown.parse(
      <<~MARKDOWN

      #{md}

      MARKDOWN
    )
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

  def inference_request(request:, print_last_message: true)
    request = JSON.parse(request)
    responses = []
    spinner = nil

    with_spinners("The Agent is...") do |spinners|
      spinner = spinners.register(
        "Sending an inference request to Heroku... :spinner",
        success_mark: "✅"
      )
      spinner.auto_spin

      stream_proc = Proc.new do |chunk, _bytesize|
        spinner.success if spinner
        responses << chunk
        spinner = spinners.register(
          "#{summarize_message(chunk.dig("choices", 0, "message"))}... :spinner",
          success_mark: "✅"
        )
        spinner.auto_spin
      end

      @client.chat(parameters: request.merge(stream: stream_proc))
    end

    # Mark the last spinner as complete
    spinner.success

    # Print the content of the last response
    if print_last_message
      print_box(responses.last.dig("choices", 0, "message", "content"))
    end

    responses.last # Return the last response
  end

  def with_spinners(action_msg, &block)
    puts "\n"
    spinners = TTY::Spinner::Multi.new(
      @pastel.call("#{action_msg}... :spinner"),
      format: :dots_2
    )
    yield(spinners)
  end

  def confirm(msg)
    @prompt.yes?(msg)
  end

  private

  def summarize_message(message)
    case message["role"]
    when "user"
      "Prompt sent."
    when "assistant"
      tool_call = message.dig("tool_calls", 0)
      if tool_call
        args = JSON.parse(tool_call.dig("function", "arguments"))

        case tool_call.dig("function", "name")
        when /\Aweb_browsing_single_page/, /\Aweb_browsing_multi_page/
          "Fetching the page #{args["url"]} ..."
        when /\Acode_exec_ruby/
          "Executing Ruby code..."
        when /\Acode_exec_python/
          "Executing Python code..."
        when /\Acode_exec_node/
          "Executing Node.js code..."
        when /\Acode_exec_go/
          "Compiling and executing Go code..."
        when /\Adatabase_get_schema/
          "Fetching the schema for the database..."
        when /\Adatabase_run_query/
          "Querying the database..."
        when /\Adyno_run_command/
          "Running the command on the Heroku dyno..."
        when "create_pie_chart"
          "The agent is requesting a local tool..."
        end
      else
        "The agent has the information it needs."
      end
    end
  end
end
