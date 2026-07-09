defmodule CnpgPhoenixDemo.Repo do
  use Ecto.Repo,
    otp_app: :cnpg_phoenix_demo,
    adapter: Ecto.Adapters.Postgres
end
