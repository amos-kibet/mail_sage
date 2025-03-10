defmodule MailSage.Factory do
  @moduledoc """
  Test factories for generating test data.
  """
  use ExMachina.Ecto, repo: MailSage.Repo

  def user_factory do
    %MailSage.Accounts.User{
      email: sequence(:email, &"user-#{&1}@example.com"),
      google_refresh_token: sequence(:token, &"refresh_token_#{&1}")
    }
  end

  def gmail_account_factory do
    %MailSage.Accounts.GmailAccount{
      user: build(:user),
      email: sequence(:email, &"gmail-#{&1}@gmail.com"),
      google_refresh_token: sequence(:token, &"refresh_token_#{&1}")
    }
  end

  def category_factory do
    %MailSage.Categories.Category{
      user: build(:user),
      name: sequence(:name, &"Category #{&1}"),
      description: sequence(:description, &"Description for category #{&1}"),
      color: "#4F46E5"
    }
  end

  def email_factory do
    %MailSage.Emails.Email{
      category: build(:category),
      user: build(:user),
      gmail_account: build(:gmail_account),
      gmail_id: sequence(:gmail_id, &"gmail_id_#{&1}")
    }
  end
end
