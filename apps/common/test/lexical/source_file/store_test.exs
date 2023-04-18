defmodule Lexical.SourceFile.StoreTest do
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position
  alias Lexical.SourceFile.Range
  use ExUnit.Case

  setup do
    {:ok, _} = start_supervised(SourceFile.Store)
    :ok
  end

  def uri do
    "file:///file.ex"
  end

  def with_an_open_document(_) do
    :ok = SourceFile.Store.open(uri(), "hello", 1)
    :ok
  end

  defp build_position(nil) do
    nil
  end

  defp build_position(opts) do
    line = Keyword.get(opts, :line)
    character = Keyword.get(opts, :character)
    Position.new(line, character)
  end

  defp build_range(nil) do
    nil
  end

  defp build_range(opts) do
    start_pos =
      opts
      |> Keyword.get(:start)
      |> build_position()

    end_pos =
      opts
      |> Keyword.get(:end)
      |> build_position()

    Range.new(start_pos, end_pos)
  end

  defp build_change(opts) do
    text = Keyword.get(opts, :text, "")

    range =
      opts
      |> Keyword.get(:range)
      |> build_range()

    %{text: text, range: range}
  end

  describe "a clean store" do
    test "a document can be opened" do
      :ok = SourceFile.Store.open(uri(), "hello", 1)
      assert {:ok, file} = SourceFile.Store.fetch(uri())
      assert SourceFile.to_string(file) == "hello"
      assert file.version == 1
    end

    test "rejects changes to a file that isn't open" do
      event = build_change(text: "dog", range: nil)

      assert {:error, :not_open} =
               SourceFile.Store.get_and_update(
                 "file:///another.ex",
                 &SourceFile.apply_content_changes(&1, 3, [event])
               )
    end
  end

  describe "a document that is already open" do
    setup [:with_an_open_document]

    test "can be fetched" do
      assert {:ok, doc} = SourceFile.Store.fetch(uri())
      assert doc.uri == uri()
      assert SourceFile.to_string(doc) == "hello"
    end

    test "can be closed" do
      assert :ok = SourceFile.Store.close(uri())
      assert {:error, :not_open} = SourceFile.Store.fetch(uri())
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
               SourceFile.Store.get_and_update(uri(), fn source_file ->
                 SourceFile.apply_content_changes(source_file, 2, [
                   event
                 ])
               end)

      assert SourceFile.to_string(doc) == "doglo"
      assert {:ok, file} = SourceFile.Store.fetch(uri())
      assert SourceFile.to_string(file) == "doglo"
    end

    test "rejects a change if the version is less than the current version" do
      event = build_change(text: "dog", range: nil)

      assert {:error, :invalid_version} =
               SourceFile.Store.get_and_update(
                 uri(),
                 &SourceFile.apply_content_changes(&1, -1, [event])
               )
    end

    test "a change cannot be applied once a file is closed" do
      event = build_change(text: "dog", range: nil)
      assert :ok = SourceFile.Store.close(uri())

      assert {:error, :not_open} =
               SourceFile.Store.get_and_update(
                 uri(),
                 &SourceFile.apply_content_changes(&1, 3, [event])
               )
    end
  end

  def with_a_temp_document(_) do
    contents = """
    defmodule FakeDocument do
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
      assert {:ok, doc} = SourceFile.Store.open_temporary(ctx.uri, 100)
      assert SourceFile.to_string(doc) == ctx.contents
    end

    test "closes after a timeout", ctx do
      assert {:ok, _} = SourceFile.Store.open_temporary(ctx.uri, 100)
      Process.sleep(101)
      refute SourceFile.Store.open?(ctx.uri)
      assert SourceFile.Store.fetch(ctx.uri) == {:error, :not_open}
    end

    test "the extension is extended on subsequent access", ctx do
      assert {:ok, _doc} = SourceFile.Store.open_temporary(ctx.uri, 100)
      Process.sleep(75)
      assert {:ok, _} = SourceFile.Store.open_temporary(ctx.uri, 100)
      Process.sleep(75)
      assert SourceFile.Store.open?(ctx.uri)
      Process.sleep(50)
      refute SourceFile.Store.open?(ctx.uri)
    end

    test "opens permanently when a call to open is made", ctx do
      assert {:ok, _doc} = SourceFile.Store.open_temporary(ctx.uri, 100)
      assert :ok = SourceFile.Store.open(ctx.uri, ctx.contents, 1)
      Process.sleep(120)
      assert SourceFile.Store.open?(ctx.uri)
    end
  end
end
