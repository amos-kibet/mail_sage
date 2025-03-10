ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(MailSage.Repo, :manual)

# Configure Mox
Mox.defmock(MailSage.MockAI, for: MailSage.Services.AI)
Mox.defmock(MailSage.MockGmail, for: MailSage.Services.Gmail)

Application.put_env(:mail_sage, :ai_client, MailSage.MockAI)
Application.put_env(:mail_sage, :gmail_client, MailSage.MockGmail)
