defmodule CnpgPhoenixDemo.NotesTest do
  use CnpgPhoenixDemo.DataCase, async: true

  alias CnpgPhoenixDemo.Notes

  test "create_note/1 round-trips through Postgres and appears in list_notes/0" do
    {:ok, note} = Notes.create_note(%{"body" => "hello from CNPG"})

    assert note.body == "hello from CNPG"
    assert [%{id: id, body: "hello from CNPG"}] = Notes.list_notes()
    assert id == note.id
  end

  test "create_note/1 broadcasts to subscribers" do
    :ok = Notes.subscribe()

    {:ok, note} = Notes.create_note(%{"body" => "live update"})
    note_id = note.id

    assert_receive {:note_created, %{id: ^note_id, body: "live update"}}
  end
end
