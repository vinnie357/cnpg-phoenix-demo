defmodule CnpgPhoenixDemo.Notes do
  @moduledoc """
  Notes stored in the CloudNativePG-managed Postgres cluster.
  """

  import Ecto.Query

  alias CnpgPhoenixDemo.Notes.Note
  alias CnpgPhoenixDemo.Repo

  @topic "notes"

  def subscribe do
    Phoenix.PubSub.subscribe(CnpgPhoenixDemo.PubSub, @topic)
  end

  def list_notes do
    Repo.all(from n in Note, order_by: [desc: n.id], limit: 50)
  end

  def create_note(attrs) do
    result =
      %Note{}
      |> Note.changeset(attrs)
      |> Repo.insert()

    with {:ok, note} <- result do
      :ok = Phoenix.PubSub.broadcast(CnpgPhoenixDemo.PubSub, @topic, {:note_created, note})
      {:ok, note}
    end
  end

  def change_note(attrs \\ %{}) do
    Note.changeset(%Note{}, attrs)
  end
end
