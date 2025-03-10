defmodule MailSage.Unsubscribe.Agent do
  @moduledoc """
  AI-powered agent for handling complex email unsubscribe flows.
  Uses browser automation and GPT for intelligent form filling and navigation.
  """

  # TODO: This is a work in progress - it's not being used, and it has not been tested!

  use GenServer

  alias MailSage.Emails.Email
  alias MailSage.Unsubscribe.BrowserSession
  alias MailSage.Unsubscribe.Metrics
  alias MailSage.Unsubscribe.Queue

  require Logger

  @retry_attempts 3
  @timeout 5 * 60

  defmodule State do
    @moduledoc false
    defstruct [:session, :email, :current_url, :attempt_count, :start_time]
  end

  # Client API

  def start_link(email) do
    GenServer.start_link(__MODULE__, email)
  end

  # Server Callbacks

  @impl true
  def init(email) do
    Process.send_after(self(), :timeout, @timeout)

    {:ok, session} = BrowserSession.start_session()

    {:ok,
     %State{
       session: session,
       email: email,
       current_url: nil,
       attempt_count: 0,
       start_time: DateTime.utc_now()
     }, {:continue, :start_unsubscribe}}
  end

  @impl true
  def handle_continue(:start_unsubscribe, state) do
    case navigate_to_unsubscribe_page(state) do
      {:ok, new_state} ->
        {:noreply, new_state, {:continue, :analyze_page}}

      {:error, reason} ->
        handle_error(reason, state)
    end
  end

  @impl true
  def handle_continue(:analyze_page, state) do
    case analyze_and_handle_page(state) do
      {:ok, :completed} ->
        handle_success(state)

      {:ok, :next_step, new_state} ->
        {:noreply, new_state, {:continue, :analyze_page}}

      {:error, reason} ->
        handle_error(reason, state)
    end
  end

  @impl true
  def handle_info(:timeout, state) do
    Logger.warning("Unsubscribe timeout for email #{state.email.id}")
    Metrics.increment(:timeout_count)
    cleanup_and_stop(state, :timeout)
  end

  # Private Functions

  defp navigate_to_unsubscribe_page(state) do
    url = state.email.unsubscribe_link

    try do
      session = state.session
      Wallaby.Browser.visit(session, url)
      {:ok, %{state | current_url: url}}
    rescue
      e ->
        Logger.error("Failed to navigate to #{url}: #{inspect(e)}")
        {:error, :navigation_failed}
    end
  end

  defp analyze_and_handle_page(state) do
    with {:ok, page_content} <- extract_page_content(state),
         {:ok, action} <- determine_next_action(page_content),
         {:ok, new_state} <- execute_action(action, state) do
      case action.type do
        :complete -> {:ok, :completed}
        _ -> {:ok, :next_step, new_state}
      end
    end
  end

  defp extract_page_content(state) do
    session = state.session

    content = %{
      text: Wallaby.Browser.text(session),
      html: Wallaby.Browser.html(session),
      forms: find_forms(session),
      buttons: find_buttons(session),
      current_url: state.current_url
    }

    {:ok, content}
  end

  defp determine_next_action(page_content) do
    prompt = build_analysis_prompt(page_content)

    case OpenAI.chat_completion(prompt) do
      {:ok, response} ->
        parse_ai_response(response)

      error ->
        Logger.error("AI analysis failed: #{inspect(error)}")
        {:error, :ai_analysis_failed}
    end
  end

  defp build_analysis_prompt(page_content) do
    """
    Analyze this webpage for unsubscribe actions. Content:
    URL: #{page_content.current_url}
    Text: #{page_content.text}
    Forms: #{inspect(page_content.forms)}
    Buttons: #{inspect(page_content.buttons)}

    Determine the next action to unsubscribe. Consider:
    1. Is this a confirmation page?
    2. Are there forms to fill?
    3. Are there buttons to click?
    4. Is this a success page?

    Respond in JSON format:
    {
      "type": "form_fill|button_click|confirmation|complete|unknown",
      "action": {
        // For form_fill:
        "fields": [{"selector": "...", "value": "..."}],
        // For button_click:
        "selector": "...",
        // For confirmation:
        "confirm": true/false
      },
      "confidence": 0.0-1.0
    }
    """
  end

  defp parse_ai_response(response) do
    case Jason.decode(response) do
      {:ok, %{"type" => type, "action" => action, "confidence" => confidence}}
      when confidence > 0.7 ->
        {:ok, %{type: String.to_atom(type), action: action, confidence: confidence}}

      _ ->
        {:error, :invalid_ai_response}
    end
  end

  defp execute_action(%{type: :form_fill, action: %{"fields" => fields}}, state) do
    Enum.each(fields, fn %{"selector" => selector, "value" => value} ->
      Wallaby.Browser.fill_in(state.session, selector, with: value)
    end)

    {:ok, state}
  end

  defp execute_action(%{type: :button_click, action: %{"selector" => selector}}, state) do
    Wallaby.Browser.click(state.session, Wallaby.Query.css(selector))
    # Wait for page load
    Process.sleep(1000)
    {:ok, %{state | current_url: Wallaby.Browser.current_url(state.session)}}
  end

  defp execute_action(%{type: :complete}, state) do
    {:ok, state}
  end

  defp execute_action(%{type: :unknown}, state) do
    {:error, :unknown_action}
  end

  defp find_forms(session) do
    session
    |> Wallaby.Browser.all("form")
    |> Enum.map(fn form ->
      %{
        id: Wallaby.Browser.attr(form, "id"),
        action: Wallaby.Browser.attr(form, "action"),
        fields: find_form_fields(form)
      }
    end)
  end

  defp find_form_fields(form) do
    form
    |> Wallaby.Browser.all("input, select, textarea")
    |> Enum.map(fn field ->
      %{
        type: Wallaby.Browser.attr(field, "type"),
        name: Wallaby.Browser.attr(field, "name"),
        id: Wallaby.Browser.attr(field, "id")
      }
    end)
  end

  defp find_buttons(session) do
    session
    |> Wallaby.Browser.all("button, input[type='submit'], a")
    |> Enum.map(fn button ->
      %{
        text: Wallaby.Browser.text(button),
        type: Wallaby.Browser.attr(button, "type"),
        href: Wallaby.Browser.attr(button, "href")
      }
    end)
  end

  defp handle_error(reason, %{attempt_count: count} = state) when count < @retry_attempts do
    Logger.warning("Unsubscribe attempt #{count + 1} failed for email #{state.email.id}: #{inspect(reason)}")

    # Exponential backoff
    Process.sleep(1000 * count)
    {:noreply, %{state | attempt_count: count + 1}, {:continue, :start_unsubscribe}}
  end

  defp handle_error(reason, state) do
    Logger.error("Unsubscribe failed for email #{state.email.id}: #{inspect(reason)}")
    Metrics.increment(:failure_count)
    cleanup_and_stop(state, reason)
  end

  defp handle_success(state) do
    Logger.info("Successfully unsubscribed email #{state.email.id}")
    Metrics.increment(:success_count)

    # Update email status
    MailSage.Emails.update_email(state.email, %{
      unsubscribed: true,
      unsubscribed_at: DateTime.utc_now()
    })

    cleanup_and_stop(state, :normal)
  end

  defp cleanup_and_stop(state, reason) do
    BrowserSession.stop_session(state.session)
    {:stop, reason, state}
  end
end
