defmodule Lexical.Server.Provider.Handlers.HoverTest do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.Proto.Convert
  alias Lexical.Protocol.Requests
  alias Lexical.Protocol.Types
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Api.Messages
  alias Lexical.Server
  alias Lexical.Server.Provider.Env
  alias Lexical.Server.Provider.Handlers
  alias Lexical.Test.Fixtures
  alias Lexical.Test.Protocol.Fixtures.LspProtocol

  import Lexical.Test.CodeSigil
  import Lexical.Test.CursorSupport

  require Messages

  use ExUnit.Case, async: false
  use Lexical.Test.PositionSupport

  setup_all do
    project = Fixtures.project()

    {:ok, _} = start_supervised(Document.Store)
    {:ok, _} = start_supervised({DynamicSupervisor, Server.Project.Supervisor.options()})
    {:ok, _} = start_supervised({Server.Project.Supervisor, project})

    :ok = RemoteControl.Api.register_listener(project, self(), [Messages.project_compiled()])
    assert_receive Messages.project_compiled(), 5000

    {:ok, project: project}
  end

  # compiles and writes beam files in the given project
  defp with_compiled_in(project, code, fun) do
    tmp_dir = Fixtures.file_path(project, "lib/tmp")

    tmp_path =
      tmp_dir
      |> Path.join("tmp_#{rand_hex(10)}.ex")

    File.mkdir_p!(tmp_dir)

    with_tmp_file(tmp_path, code, fn ->
      {:ok, compile_path} =
        RemoteControl.Mix.in_project(project, fn _ ->
          Mix.Project.compile_path()
        end)

      {:ok, modules, _} =
        RemoteControl.call(project, Kernel.ParallelCompiler, :compile_to_path, [
          [tmp_path],
          compile_path
        ])

      try do
        fun.()
      after
        for module <- modules do
          path = RemoteControl.call(project, :code, :which, [module])
          RemoteControl.call(project, :code, :delete, [module])
          File.rm!(path)
        end
      end
    end)
  end

  defp rand_hex(n_bytes) do
    n_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.hex_encode32()
  end

  defp with_tmp_file(file, content, fun) do
    File.write!(file, content)
    fun.()
  after
    File.rm_rf!(file)
  end

  describe "module hover" do
    test "with @moduledoc", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule HoverWithDoc do
            @moduledoc """
            This module has a moduledoc.
            """
          end
        ],
        hovered: "|HoverWithDoc",
        expected: """
        ```elixir
        HoverWithDoc
        ```

        ---

        This module has a moduledoc.
        """
      )
    end

    test "with @moduledoc false", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule HoverPrivate do
            @moduledoc false
          end
        ],
        hovered: "|HoverPrivate",
        expected: nil
      )
    end

    test "without @moduledoc", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule HoverNoDocs do
          end
        ],
        hovered: "|HoverNoDocs",
        expected: nil
      )
    end

    test "with behaviour callbacks", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule HoverBehaviour do
            @moduledoc "This is a custom behaviour."

            @type custom_type :: term()

            @callback foo(integer(), float()) :: custom_type
            @callback bar(term()) :: {:ok, custom_type}
          end
        ],
        hovered: "|HoverBehaviour",
        expected: """
        ```elixir
        HoverBehaviour
        ```

        ---

        This is a custom behaviour.

        ---

        #### Callbacks

        ```elixir
        @callback bar(term()) :: {:ok, custom_type()}
        @callback foo(integer(), float()) :: custom_type()
        ```
        """
      )
    end

    test "struct with @moduledoc includes t/0 type", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule StructWithDoc do
            @moduledoc """
            This module has a moduledoc.
            """

            defstruct foo: nil, bar: nil, baz: nil
            @type t :: %__MODULE__{
                    foo: String.t(),
                    bar: integer(),
                    baz: {boolean(), reference()}
                  }
          end
        ],
        hovered: "%|StructWithDoc{}",
        expected: """
        ```elixir
        %StructWithDoc{}
        ```

        ---

        #### Struct

        ```elixir
        @type t() :: %StructWithDoc{
                bar: integer(),
                baz: {boolean(), reference()},
                foo: String.t()
              }
        ```

        ---

        This module has a moduledoc.
        """
      )
    end

    test "struct with @moduledoc includes all t types", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule StructWithDoc do
            @moduledoc """
            This module has a moduledoc.
            """

            defstruct foo: nil
            @type t :: %__MODULE__{foo: String.t()}
            @type t(kind) :: %__MODULE__{foo: kind}
            @type t(kind1, kind2) :: %__MODULE__{foo: {kind1, kind2}}
          end
        ],
        hovered: "%|StructWithDoc{}",
        expected: """
        ```elixir
        %StructWithDoc{}
        ```

        ---

        #### Struct

        ```elixir
        @type t() :: %StructWithDoc{foo: String.t()}
        @type t(kind) :: %StructWithDoc{foo: kind}
        @type t(kind1, kind2) :: %StructWithDoc{foo: {kind1, kind2}}
        ```

        ---

        This module has a moduledoc.
        """
      )
    end

    test "struct with @moduledoc without type", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule StructWithDoc do
            @moduledoc """
            This module has a moduledoc.
            """

            defstruct foo: nil
          end
        ],
        hovered: "%|StructWithDoc{}",
        expected: """
        ```elixir
        %StructWithDoc{}
        ```

        ---

        This module has a moduledoc.
        """
      )
    end
  end

  describe "call hover" do
    test "public function with @doc and @spec", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule CallHover do
            @doc """
            This function has docs.
            """
            @spec my_fun(integer(), integer()) :: integer()
            def my_fun(x, y), do: x + y
          end
        ],
        hovered: "CallHover.|my_fun(1, 2)",
        expected: """
        ```elixir
        CallHover.my_fun(x, y)
        ```

        ---

        #### Specs

        ```elixir
        @spec my_fun(integer(), integer()) :: integer()
        ```

        ---

        This function has docs.
        """
      )
    end

    test "public function with multiple @spec", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule CallHover do
            @spec my_fun(integer(), integer()) :: integer()
            @spec my_fun(float(), float()) :: float()
            def my_fun(x, y), do: x + y
          end
        ],
        hovered: "CallHover.|my_fun(1, 2)",
        expected: """
        ```elixir
        CallHover.my_fun(x, y)
        ```

        ---

        #### Specs

        ```elixir
        @spec my_fun(integer(), integer()) :: integer()
        @spec my_fun(float(), float()) :: float()
        ```
        """
      )
    end

    test "public function with multiple arities and @spec", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule CallHover do
            @spec my_fun(integer()) :: integer()
            def my_fun(x), do: x + 1

            @spec my_fun(integer(), integer()) :: integer()
            def my_fun(x, y), do: x + y

            @spec my_fun(integer(), integer(), integer()) :: integer()
            def my_fun(x, y, z), do: x + y + z
          end
        ],
        hovered: "CallHover.|my_fun(1, 2)",
        expected: """
        ```elixir
        CallHover.my_fun(x, y)
        ```

        ---

        #### Specs

        ```elixir
        @spec my_fun(integer(), integer()) :: integer()
        ```

        ---

        ```elixir
        CallHover.my_fun(x, y, z)
        ```

        ---

        #### Specs

        ```elixir
        @spec my_fun(integer(), integer(), integer()) :: integer()
        ```
        """
      )
    end

    test "private function", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule CallHover do
            @spec my_fun(integer()) :: integer()
            defp my_fun(x), do: x + 1

            def my_other_fun(x, y), do: my_fun(x) + my_fun(y)
          end
        ],
        hovered: "CallHover.|my_fun(1)",
        expected: nil
      )
    end

    test "private function with public function of same name", %{project: project} do
      assert_hover(
        project,
        code: ~q[
          defmodule CallHover do
            @spec my_fun(integer()) :: integer()
            defp my_fun(x), do: x + 1

            def my_fun(x, y), do: my_fun(x) + my_fun(y)
          end
        ],
        hovered: "CallHover.|my_fun(1)",
        expected: """
        ```elixir
        CallHover.my_fun(x, y)
        ```
        """
      )
    end
  end

  defp assert_hover(project, opts) do
    code = Keyword.fetch!(opts, :code)
    hovered = Keyword.fetch!(opts, :hovered)
    expected = Keyword.fetch!(opts, :expected)

    with_compiled_in(project, code, fn ->
      if expected do
        assert {:reply, %{result: %Types.Hover{} = result}} = hover(project, hovered)
        assert result.contents.kind == :markdown
        assert result.contents.value == expected
      else
        assert {:reply, %{result: nil}} = hover(project, hovered)
      end
    end)
  end

  defp hover(project, hovered) do
    with {position, hovered} <- pop_position(hovered),
         {:ok, document} <- document_with_content(project, hovered),
         {:ok, request} <- hover_request(document.uri, position) do
      Handlers.Hover.handle(request, %Env{project: project})
    end
  end

  defp pop_position(code) do
    {line, character} = cursor_position(code)
    {position(line, character), strip_cursor(code)}
  end

  defp document_with_content(project, content) do
    uri =
      project
      |> Fixtures.file_path(Path.join("lib", "my_doc.ex"))
      |> Document.Path.ensure_uri()

    case Document.Store.open(uri, content, 1) do
      :ok ->
        Document.Store.fetch(uri)

      {:error, :already_open} ->
        Document.Store.close(uri)
        document_with_content(project, content)

      error ->
        error
    end
  end

  defp hover_request(path, %Position{} = position) do
    hover_request(path, position.line, position.character)
  end

  defp hover_request(path, line, char) do
    uri = Document.Path.ensure_uri(path)

    # convert line and char to zero-based
    params = [
      position: [line: line - 1, character: char - 1],
      text_document: [uri: uri]
    ]

    with {:ok, _} <- Document.Store.open_temporary(uri),
         {:ok, req} <- LspProtocol.build(Requests.Hover, params) do
      Convert.to_native(req)
    end
  end
end
