# credo:disable-for-this-file Credo.Check.Readability.RedundantBlankLines
defmodule Lexical.RemoteControl.CodeMod.FormatTest do
  alias Lexical.Document
  alias Lexical.Project
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.RemoteControl.Build
  alias Lexical.RemoteControl.CodeMod.Format
  alias Lexical.RemoteControl.Commands

  use Lexical.Test.CodeMod.Case, enable_ast_conversion: false
  use Patch
  import Messages

  def apply_code_mod(text, _ast, opts) do
    project = Keyword.get(opts, :project)

    file_uri =
      opts
      |> Keyword.get(:file_path, file_path(project))
      |> maybe_uri()

    with {:ok, document_edits} <- Format.edits(document(file_uri, text)) do
      {:ok, document_edits.edits}
    end
  end

  def maybe_uri(path_or_uri) when is_binary(path_or_uri), do: Document.Path.to_uri(path_or_uri)
  def maybe_uri(not_binary), do: not_binary

  def document(file_uri, text) do
    Document.new(file_uri, text, 1)
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

  def with_real_project(%{project: project}) do
    {:ok, _} = start_supervised({RemoteControl.ProjectNodeSupervisor, project})
    {:ok, _, _} = RemoteControl.start_link(project)
    RemoteControl.Api.register_listener(project, self(), [:all])
    :ok
  end

  def with_patched_build(_) do
    patch(Build, :compile_document, fn _, _ -> :ok end)
    :ok
  end

  setup do
    start_supervised!(Commands.Rename)
    project = project()
    RemoteControl.set_project(project)
    {:ok, project: project}
  end

  describe "format/2" do
    setup [:with_patched_build]

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
    setup [:with_real_project]

    test "it should emit diagnostics when a syntax error occurs", %{project: project} do
      text = ~q[
        def foo(a, ) do
        end
        ]
      document = document("file:///file.ex", text)
      RemoteControl.Api.format(project, document)

      assert_receive file_diagnostics(diagnostics: [diagnostic]), 500
      assert diagnostic.message =~ "syntax error"
    end
  end
end
