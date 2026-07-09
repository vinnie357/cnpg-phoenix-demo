defmodule CnpgPhoenixDemo.Notes do
  @moduledoc """
  Notes stored in the CloudNativePG-managed Postgres cluster.
  """

  import Ecto.Query

  alias CnpgPhoenixDemo.Notes.Note
  alias CnpgPhoenixDemo.Repo

  def list_notes do
    Repo.all(from n in Note, order_by: [desc: n.id], limit: 50)
  end

  def create_note(attrs) do
    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  def change_note(attrs \\ %{}) do
    Note.changeset(%Note{}, attrs)
  end
end
