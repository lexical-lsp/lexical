defmodule Lexical.Document.StoreTest do
  alias Lexical.Document
  alias Lexical.Document.Edit
  alias Lexical.Document.Position
  alias Lexical.Document.Range

  use ExUnit.Case

  setup do
    {:ok, _} = start_supervised(Document.Store)
    :ok
  end

  def uri do
    "file:///file.ex"
  end

  def with_an_open_document(_) do
    :ok = Document.Store.open(uri(), "hello", 1)
    :ok
  end

  defp build_position(_, nil) do
    nil
  end

  defp build_position(%Document{} = document, opts) do
    line = Keyword.get(opts, :line)
    character = Keyword.get(opts, :character)
    Position.new(document, line, character)
  end

  defp build_range(_, nil) do
    nil
  end

  defp build_range(%Document{} = document, opts) do
    start_pos = build_position(document, Keyword.get(opts, :start))

    end_pos = build_position(document, Keyword.get(opts, :end))

    Range.new(start_pos, end_pos)
  end

  defp build_change(opts) do
    text = Keyword.get(opts, :text, "")
    document = Document.new("file:///file.ex", text, 1)

    range = build_range(document, Keyword.get(opts, :range))
    Edit.new(text, range)
  end

  describe "a clean store" do
    test "a document can be opened" do
      :ok = Document.Store.open(uri(), "hello", 1)
      assert {:ok, file} = Document.Store.fetch(uri())
      assert Document.to_string(file) == "hello"
      assert file.version == 1
    end

    test "rejects changes to a file that isn't open" do
      event = build_change(text: "dog", range: nil)

      assert {:error, :not_open} =
               Document.Store.get_and_update(
                 "file:///another.ex",
                 &Document.apply_content_changes(&1, 3, [event])
               )
    end
  end

  describe "a document that is already open" do
    setup [:with_an_open_document]

    test "can be fetched" do
      assert {:ok, doc} = Document.Store.fetch(uri())
      assert doc.uri == uri()
      assert Document.to_string(doc) == "hello"
    end

    test "can be closed" do
      assert :ok = Document.Store.close(uri())
      assert {:error, :not_open} = Document.Store.fetch(uri())
    end

    test "can be saved" do
      assert :ok = Document.Store.save(uri())
      assert {:ok, %{dirty?: false}} = Document.Store.fetch(uri())
    end

    test "can have its content changed" do
      event =
        build_change(
          text: "dog",
          range: [
            start: [line: 1, character: 1],
            end: [line: 1, character: 4]
          ]
        )

      assert {:ok, doc} =
               Document.Store.get_and_update(uri(), fn document ->
                 Document.apply_content_changes(document, 2, [
                   event
                 ])
               end)

      assert Document.to_string(doc) == "doglo"
      assert {:ok, file} = Document.Store.fetch(uri())
      assert Document.to_string(file) == "doglo"
    end

    test "rejects a change if the version is less than the current version" do
      event = build_change(text: "dog", range: nil)

      assert {:error, :invalid_version} =
               Document.Store.get_and_update(
                 uri(),
                 &Document.apply_content_changes(&1, -1, [event])
               )
    end

    test "a change cannot be applied once a file is closed" do
      event = build_change(text: "dog", range: nil)
      assert :ok = Document.Store.close(uri())

      assert {:error, :not_open} =
               Document.Store.get_and_update(
                 uri(),
                 &Document.apply_content_changes(&1, 3, [event])
               )
    end
  end

  def with_a_temp_document(_) do
    contents = """
    defmodule FakeLines do
    end
    """

    :ok = File.write("/tmp/file.ex", contents)

    on_exit(fn ->
      File.rm!("/tmp/file.ex")
    end)

    {:ok, contents: contents, uri: "file:///tmp/file.ex"}
  end

  describe "a temp document" do
    setup [:with_a_temp_document]

    test "can be opened", ctx do
      assert {:ok, doc} = Document.Store.open_temporary(ctx.uri, 100)
      assert Document.to_string(doc) == ctx.contents
    end

    test "closes after a timeout", ctx do
      assert {:ok, _} = Document.Store.open_temporary(ctx.uri, 100)
      Process.sleep(101)
      refute Document.Store.open?(ctx.uri)
      assert Document.Store.fetch(ctx.uri) == {:error, :not_open}
    end

    test "the extension is extended on subsequent access", ctx do
      assert {:ok, _doc} = Document.Store.open_temporary(ctx.uri, 100)
      Process.sleep(75)
      assert {:ok, _} = Document.Store.open_temporary(ctx.uri, 100)
      Process.sleep(75)
      assert Document.Store.open?(ctx.uri)
      Process.sleep(50)
      refute Document.Store.open?(ctx.uri)
    end

    test "opens permanently when a call to open is made", ctx do
      assert {:ok, _doc} = Document.Store.open_temporary(ctx.uri, 100)
      assert :ok = Document.Store.open(ctx.uri, ctx.contents, 1)
      Process.sleep(120)
      assert Document.Store.open?(ctx.uri)
    end
  end
end
