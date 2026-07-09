defmodule CnpgPhoenixDemo.NotesTest do
  use CnpgPhoenixDemo.DataCase, async: true

  alias CnpgPhoenixDemo.Notes

  test "create_note/1 round-trips through Postgres and appears in list_notes/0" do
    {:ok, note} = Notes.create_note(%{"body" => "hello from CNPG"})

    assert note.body == "hello from CNPG"
    assert [%{id: id, body: "hello from CNPG"}] = Notes.list_notes()
    assert id == note.id
  end
end
