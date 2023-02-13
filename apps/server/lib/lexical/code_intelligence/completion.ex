defmodule Lexical.CodeIntelligence.Completion do
  alias Lexical.Project
  alias Lexical.Protocol.Types.Completion
  alias Lexical.Protocol.Types.InsertTextFormat
  alias Lexical.RemoteControl
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.SourceFile
  alias Lexical.SourceFile.Position

  require InsertTextFormat
  require Logger

  @lexical_deps Enum.map([:lexical | Mix.Project.deps_apps()], &Atom.to_string/1)

  @lexical_dep_modules Enum.map(@lexical_deps, &Macro.camelize/1)

  def trigger_characters do
    [".", "@", "&", "%", "^", ":", "!", "-", "~"]
  end

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
    |> to_completion_items(project, position)
  end

  defp to_completion_items(local_completions, %Project{} = project, %Position{} = position) do
    for result <- local_completions,
        displayable?(project, result),
        item = to_completion_item(result, position),
        match?(%Completion.Item{}, item) do
      item
    end
  end

  defp displayable?(%Project{} = project, result) do
    # Don't exclude a dependency if we're working on that project!
    if Project.name(project) in @lexical_deps do
      true
    else
      suggested_module =
        case result do
          %_{full_name: full_name} -> full_name
          %_{origin: origin} -> origin
          _ -> ""
        end

      Enum.reduce_while(@lexical_dep_modules, true, fn module, _ ->
        if String.starts_with?(suggested_module, module) do
          {:halt, false}
        else
          {:cont, true}
        end
      end)
    end
  end

  defp to_completion_item(%Result.Function{} = function, %Position{}) do
    label = "#{function.name}/#{function.arity}"
    arg_detail = Enum.join(function.argument_names, ",")
    detail = "#{function.origin}.#{label}(#{arg_detail})"

    insert_text = "#{function.name}($0)"
    sort_text = String.replace(label, "__", "")

    tags =
      if Map.get(function.metadata, :deprecated) do
        [:deprecated]
      end

    Completion.Item.new(
      detail: detail,
      insert_text: insert_text,
      insert_text_format: :snippet,
      kind: :function,
      label: label,
      sort_text: sort_text,
      tags: tags
    )
  end

  defp to_completion_item(%Result.StructField{name: "__struct__"}, %Position{}) do
    :skip
  end

  defp to_completion_item(%Result.StructField{} = struct_field, %Position{}) do
    Completion.Item.new(
      label: struct_field.name,
      kind: :field
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

  defp to_completion_item(%Result.Macro{name: name}, %Position{})
       when name in ["__before_compile__", "__using__", "__after_compile__"] do
    :skip
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
    sort_text = String.replace(label, "__", "")
    Completion.Item.new(label: label, kind: :function, detail: macro.spec, sort_text: sort_text)
  end

  defp to_completion_item(_skip, _) do
    :skip
  end
end
