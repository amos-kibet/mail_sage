defmodule MailSage.Services.OpenAI do
  @moduledoc """
  Custom OpenAI client using Finch.
  """

  @api_url "https://api.openai.com/v1"

  def chat_completion(messages, opts \\ []) do
    model = opts[:model] || "gpt-3.5-turbo"
    temperature = opts[:temperature] || 0.7
    max_tokens = opts[:max_tokens] || 150

    request =
      Finch.build(
        :post,
        "#{@api_url}/chat/completions",
        [
          {"Authorization", "Bearer #{api_key()}"},
          {"Content-Type", "application/json"}
        ],
        Jason.encode!(%{
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        })
      )

    case Finch.request(request, MailSage.Finch) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        {:ok, Jason.decode!(body)}

      {:ok, %Finch.Response{body: body}} ->
        {:error, Jason.decode!(body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp api_key do
    Application.fetch_env!(:mail_sage, :openai_api_key)
  end
end
