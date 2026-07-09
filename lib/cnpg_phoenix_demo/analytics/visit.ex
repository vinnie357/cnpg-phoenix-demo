defmodule CnpgPhoenixDemo.Analytics.Visit do
  use Ecto.Schema
  import Ecto.Changeset

  schema "visits" do
    field :pod, :string
    field :node, :string
    timestamps(updated_at: false)
  end

  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:pod, :node])
    |> validate_required([:pod, :node])
  end
end
