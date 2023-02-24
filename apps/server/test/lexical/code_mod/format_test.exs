defmodule Lexical.Server.CodeMod.FormatTest do
  alias Lexical.Project
  alias Lexical.CodeMod.Format
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.SourceFile

  use Lexical.Test.CodeMod.Case
  use Patch
  import Messages

  def apply_code_mod(text, _ast, opts) do
    project = Keyword.get(opts, :project)

    file_uri =
      opts
      |> Keyword.get(:file_path, file_path(project))
      |> maybe_uri()

    Format.text_edits(project, source_file(file_uri, text))
  end

  def maybe_uri(path_or_uri) when is_binary(path_or_uri), do: SourceFile.Path.to_uri(path_or_uri)
  def maybe_uri(not_binary), do: not_binary

  def source_file(file_uri, text) do
    SourceFile.new(file_uri, text, 1)
  end

  def file_path(project) do
    Path.join([Project.root_path(project), "lib", "format.ex"])
  end

  def unformatted do
    ~q[
    defmodule Unformatted do
      def something(  a,     b  ) do
    end
    end
    ]t
  end

  def formatted do
    ~q[
    defmodule Unformatted do
      def something(a, b) do
      end
    end
    ]t
  end

  def with_forwarded_listener(_) do
    :ok
  end

  setup do
    project = project()
    {:ok, _} = RemoteControl.start_link(project, self())

    on_exit(fn ->
      :ok = RemoteControl.stop(project)
    end)

    {:ok, project: project}
  end

  describe "format/2" do
    test "it should be able to format a file in the project", %{project: project} do
      {:ok, result} = modify(unformatted(), project: project)

      assert result == formatted()
    end

    test "it will fail to format a file not in the project", %{project: project} do
      assert {:error, reason} = modify(unformatted(), file_path: "/tmp/foo.ex", project: project)
      assert reason =~ "Cannot format file /tmp/foo.ex"
      assert reason =~ "It is not in the project at"
    end

    test "it should provide an error for a syntax error", %{project: project} do
      assert {:error, %SyntaxError{}} = ~q[
      def foo(a, ) do
        true
      end
      ] |> modify(project: project)
    end

    test "it should provide an error for a missing token", %{project: project} do
      assert {:error, %TokenMissingError{}} = ~q[
      defmodule TokenMissing do
       :bad
      ] |> modify(project: project)
    end

    test "it correctly handles unicode", %{project: project} do
      assert {:ok, result} = ~q[
        {"🎸",    "o"}
      ] |> modify(project: project)

      assert ~q[
        {"🎸", "o"}
      ]t == result
    end

    test "it handles extra lines", %{project: project} do
      assert {:ok, result} = ~q[
        defmodule  Unformatted do
          def something(    a        ,   b) do



          end
      end
      ] |> modify(project: project)

      assert result == formatted()
    end
  end

  describe "emitting diagnostics" do
    setup [:with_forwarded_listener]

    test "it should emit diagnostics when a syntax error occurs", %{project: project} do
      assert {:error, _} = ~q[
        def foo(a, ) do
      end
      ] |> modify(project: project)

      assert_receive file_diagnostics(diagnostics: [diagnostic])
      assert diagnostic.message =~ "syntax error"
    end
  end
end
