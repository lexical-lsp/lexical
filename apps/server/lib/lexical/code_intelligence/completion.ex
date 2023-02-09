defmodule Lexical.CodeIntelligence.Completion do
  alias Lexical.Protocol.Types.InsertTextFormat
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion

  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position

  require InsertTextFormat
  require Logger

  @spec complete(Project.t(), SourceFile.t(), Position.t(), Completion.Context.t()) :: [
          Completion.Item
        ]
  def complete(
        %Project{} = project,
        %SourceFile{} = document,
        %Position{} = position,
        %Completion.Context{} = _context
      ) do
    project
    |> RemoteControl.Api.complete(document, position)
    |> tap(&Logger.info("Got #{inspect(Enum.take(&1, 10))}"))
    |> to_completion_items(position)
    |> tap(&Logger.info("Emitting #{inspect(Enum.take(&1, 10))}"))
  end

  defp to_completion_items(local_completions, %Position{} = position) do
    for result <- local_completions,
        item = to_completion_item(result, position),
        match?(%Completion.Item{}, item) do
      item
    end
  end

  defp to_completion_item(%Result.Function{} = function, %Position{}) do
    label = "#{function.name}/#{function.arity}"
    arg_detail = Enum.join(function.argument_names, ",")
    detail = "#{function.origin}.#{label}(#{arg_detail})"

    arg_snippet =
      function.argument_names
      |> Enum.with_index()
      |> Enum.map_join(", ", fn {arg_name, index} -> "${#{index + 1}:#{arg_name}}" end)

    insert_text = "#{function.name}(#{arg_snippet})"

    Completion.Item.new(
      detail: detail,
      insert_text: insert_text,
      insert_text_format: :snippet,
      kind: :function,
      label: label
    )
  end

  defp to_completion_item(%Result.Module{} = module, %Position{}) do
    Completion.Item.new(
      label: module.name,
      kind: :module,
      detail: module.summary
    )
  end

  defp to_completion_item(%Result.ModuleAttribute{} = attribute, %Position{}) do
    Completion.Item.new(
      kind: :constant,
      label: attribute.name,
      insert_text: String.slice(attribute.name, 1..-1)
    )
  end

  defp to_completion_item(%Result.Variable{} = variable, %Position{}) do
    Completion.Item.new(
      detail: variable.name,
      kind: :variable,
      label: variable.name
    )
  end

  defp to_completion_item(%Result.Struct{} = struct, %Position{}) do
    Completion.Item.new(
      detail: "#{struct.name} (Struct)",
      kind: :struct,
      label: struct.name
    )
  end

  defp to_completion_item(%Result.Macro{name: "def", arity: 2} = macro, %Position{}) do
    label = "#{macro.name} (Define a function)"

    snippet = """
    def ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{name: "defp", arity: 2} = macro, %Position{}) do
    label = "#{macro.name} (Define a private function)"

    snippet = """
    defp ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{name: "defmacro", arity: 2} = macro, %Position{}) do
    label = "#{macro.name} (Define a macro)"

    snippet = """
    defmacro ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{name: "defmacrop", arity: 2} = macro, %Position{}) do
    label = "#{macro.name} (Define a private macro)"

    snippet = """
    defmacrop ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{name: "defmodule"} = macro, %Position{}) do
    label = "defmodule (Define a module)"

    snippet = """
    defmodule ${1:module name} do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{name: "defprotocol"} = macro, %Position{}) do
    label = "#{macro.name} (Define a protocol)"

    snippet = """
    defprotocol ${1:protocol name} do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{name: "defimpl", arity: 3} = macro, %Position{}) do
    label = "#{macro.name} (Define a protocol implementation)"

    snippet = """
    defimpl ${1:protocol name}, for: ${2:type} do
      $0
    end
    """

    Completion.Item.new(
      label: label,
      kind: :class,
      insert_text: snippet,
      insert_text_format: :snippet,
      detail: macro.spec
    )
  end

  defp to_completion_item(%Result.Macro{} = macro, %Position{}) do
    label = "#{macro.name}/#{macro.arity}"

    Completion.Item.new(label: label, kind: :function, detail: macro.spec)
  end

  defp to_completion_item(_, _), do: :skip
end
