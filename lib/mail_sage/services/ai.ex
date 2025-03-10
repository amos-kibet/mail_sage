defmodule MailSage.Services.AI do
  @moduledoc """
  Behaviour for AI service operations - categorization and summarization
  """

  alias ExOpenAI.Chat
  alias ExOpenAI.Components.ChatCompletionRequestSystemMessage
  alias ExOpenAI.Components.ChatCompletionRequestUserMessage
  alias MailSage.Categories
  alias MailSage.Emails.Email

  require Logger

  @callback categorize_email(map(), String.t()) ::
              {:ok, String.t()} | {:error, any()}

  @callback summarize_email(map()) ::
              {:ok, String.t()} | {:error, any()}

  @open_ai_chat_opts [temperature: 0.3, max_tokens: 50]

  @max_retries 3
  # 1 second in milliseconds
  @initial_delay 1000

  @doc """
  Categorizes an email using AI by comparing it against category descriptions.
  Returns the best matching category ID.
  """
  def categorize_email(%Email{} = email, user_id) do
    categories = Categories.list_categories(user_id)

    if Enum.empty?(categories) do
      {:error, :no_categories}
    else
      email_content = build_email_content(email)
      category_names = Enum.map(categories, & &1.name)
      category_descriptions = build_category_descriptions(categories)

      messages = [
        %ChatCompletionRequestSystemMessage{
          role: "system",
          content: """
          You are an email categorizer. Given an email and a list of categories with descriptions,
          determine the best matching category. You must only respond with one of these exact category names:
          #{Enum.join(category_names, ", ")}
          """
        },
        %ChatCompletionRequestUserMessage{
          role: "user",
          content: """
          Categories:
          #{category_descriptions}

          Email:
          #{email_content}

          Which category best matches this email? Respond with just the category name from the list provided.
          """
        }
      ]

      with {:ok, response} <-
             make_api_call_with_backoff(fn ->
               Chat.create_chat_completion(messages, "gpt-3.5-turbo", @open_ai_chat_opts)
             end),
           %{choices: [%{message: %{content: category_name}} | _]} <- response,
           category when not is_nil(category) <-
             Enum.find(categories, &(&1.name == String.trim(category_name))) do
        {:ok, category.id}
      else
        nil ->
          Logger.error("#{__MODULE__}.categorize_email/2 No matching category found!")
          {:error, :no_matching_category}

        error ->
          Logger.error("#{__MODULE__}.categorize_email/2 Error categorizing email\n#{inspect(error)}")

          error
      end
    end
  end

  @doc """
  Generates a concise summary of an email using AI.
  """
  def summarize_email(%Email{} = email) do
    content = build_email_content(email)

    messages = [
      %ChatCompletionRequestSystemMessage{
        role: "system",
        content: "You are an email summarizer. Create a brief, clear summary of the email content."
      },
      %ChatCompletionRequestUserMessage{
        role: "user",
        content: "Summarize this email in 2-3 sentences: #{content}"
      }
    ]

    case make_api_call_with_backoff(fn ->
           Chat.create_chat_completion(messages, "gpt-3.5-turbo", @open_ai_chat_opts)
         end) do
      {:ok, %{choices: [%{message: %{content: summary}} | _]}} ->
        {:ok, String.trim(summary)}

      error ->
        Logger.error("#{__MODULE__}.summarize_email/1 Error summarizing email\n#{inspect(error)}")
        error
    end
  end

  # Private functions

  defp make_api_call_with_backoff(api_call, retry_count \\ 0) do
    case api_call.() do
      {:error, %{status: 429}} when retry_count < @max_retries ->
        # Calculate delay with exponential backoff: 2^retry_count * initial_delay
        delay = trunc(:math.pow(2, retry_count) * @initial_delay)

        Logger.warning("Rate limited by OpenAI. Retrying in #{delay}ms (attempt #{retry_count + 1}/#{@max_retries})")

        Process.sleep(delay)
        make_api_call_with_backoff(api_call, retry_count + 1)

      {:error, %{status: 429}} ->
        Logger.error("Max retries reached for OpenAI API call")
        {:error, :rate_limit_exceeded}

      result ->
        result
    end
  end

  defp build_email_content(%Email{} = email) do
    """
    Subject: #{email.subject}
    From: #{email.from}
    Snippet: #{email.snippet}
    Body: #{email.body_text || email.body_html || ""}
    """
  end

  defp build_category_descriptions(categories) do
    Enum.map_join(categories, "\n", &"#{&1.name}: #{&1.description || &1.name}")
  end
end
