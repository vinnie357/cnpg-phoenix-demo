defmodule CnpgPhoenixDemo.AnalyticsRepo do
  @moduledoc """
  Second data domain: a separate CNPG cluster (metrics-db) for event data.
  Optional — only started when ANALYTICS_DATABASE_URL is configured.
  """
  use Ecto.Repo,
    otp_app: :cnpg_phoenix_demo,
    adapter: Ecto.Adapters.Postgres
end
