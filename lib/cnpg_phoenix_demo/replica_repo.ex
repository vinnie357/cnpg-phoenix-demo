defmodule CnpgPhoenixDemo.ReplicaRepo do
  @moduledoc """
  Read-only pool aimed at the CNPG `-ro` service (hot standbys).
  Falls back to the primary's DATABASE_URL when DATABASE_RO_URL is unset,
  so single-instance clusters and local dev keep working.
  """
  use Ecto.Repo,
    otp_app: :cnpg_phoenix_demo,
    adapter: Ecto.Adapters.Postgres,
    read_only: true
end
