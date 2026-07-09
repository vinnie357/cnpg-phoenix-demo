defmodule CnpgPhoenixDemo.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field :body, :string
    timestamps(updated_at: false)
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, max: 280)
  end
end
