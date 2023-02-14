defmodule Lexical.CodeIntelligence.Completion do
  alias Lexical.Server.Project.Intelligence
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

  @snippet_macros ~w(def defp defmacro defmacrop defimpl defmodule defprotocol defguard defguardp defexception)

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
        %Completion.Context{} = context
      ) do
    project
    |> RemoteControl.Api.complete(document, position)
    |> to_completion_items(project, context)
  end

  defp to_completion_items(
         local_completions,
         %Project{} = project,
         %Completion.Context{} = context
       ) do
    for result <- local_completions,
        displayable?(project, result),
        applies_to_context?(project, result, context),
        item = to_completion_item(result),
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

  defp applies_to_context?(
         %Project{} = project,
         result,
         %Completion.Context{
           trigger_kind: :trigger_character,
           trigger_character: "%"
         }
       ) do
    case result do
      %Result.Module{} = result ->
        Intelligence.child_defines_struct?(project, result.full_name)

      %Result.Struct{} ->
        true

      _other ->
        false
    end
  end

  defp applies_to_context?(_project, _result, _context) do
    true
  end

  defp to_completion_item(%Result.Function{} = function) do
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

  defp to_completion_item(%Result.StructField{name: "__struct__"}) do
    :skip
  end

  defp to_completion_item(%Result.StructField{} = struct_field) do
    Completion.Item.new(
      label: struct_field.name,
      kind: :field
    )
  end

  defp to_completion_item(%Result.Module{} = module) do
    Completion.Item.new(
      label: module.name,
      kind: :module,
      detail: module.summary
    )
  end

  defp to_completion_item(%Result.ModuleAttribute{} = attribute) do
    Completion.Item.new(
      kind: :constant,
      label: attribute.name,
      insert_text: String.slice(attribute.name, 1..-1)
    )
  end

  defp to_completion_item(%Result.Variable{} = variable) do
    Completion.Item.new(
      detail: variable.name,
      kind: :variable,
      label: variable.name
    )
  end

  defp to_completion_item(%Result.Struct{} = struct) do
    Completion.Item.new(
      detail: "#{struct.name} (Struct)",
      kind: :struct,
      label: struct.name
    )
  end

  defp to_completion_item(%Result.Macro{name: name})
       when name in ["__before_compile__", "__using__", "__after_compile__"] do
    :skip
  end

  defp to_completion_item(%Result.Macro{name: "defmodule"} = macro) do
    label = "defmodule (Define a module)"

    snippet = """
    defmodule ${1:module name} do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label, 10)
    )
  end

  defp to_completion_item(%Result.Macro{name: "def", arity: 2} = macro) do
    label = "#{macro.name} (Define a function)"

    snippet = """
    def ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label, 9)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defp", arity: 2} = macro) do
    label = "#{macro.name} (Define a private function)"

    snippet = """
    defp ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label, 8)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defmacro", arity: 2} = macro) do
    label = "#{macro.name} (Define a macro)"

    snippet = """
    defmacro ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label, 7)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defmacrop", arity: 2} = macro) do
    label = "#{macro.name} (Define a private macro)"

    snippet = """
    defmacrop ${1:name}($2) do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label, 6)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defprotocol"} = macro) do
    label = "#{macro.name} (Define a protocol)"

    snippet = """
    defprotocol ${1:protocol name} do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defimpl", arity: 3} = macro) do
    label = "#{macro.name} (Define a protocol implementation)"

    snippet = """
    defimpl ${1:protocol name}, for: ${2:type} do
      $0
    end
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defdelegate", arity: 2} = macro) do
    label = "#{macro.name} (Define a delegate function)"

    snippet = """
    defdelegate ${1:call}, to: ${2:module} $0
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defguard", arity: 1} = macro) do
    label = "#{macro.name} (Define a guard macro)"

    snippet = """
    defguard ${1:call} $0
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defguardp", arity: 1} = macro) do
    label = "#{macro.name} (Define a private guard macro)"

    snippet = """
    defguardp ${1:call} $0
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label)
    )
  end

  defp to_completion_item(%Result.Macro{name: "defexception", arity: 1} = macro) do
    label = "#{macro.name} (Define an exception)"

    snippet = """
    defexception [${1:fields}] $0
    """

    Completion.Item.new(
      detail: macro.spec,
      insert_text: snippet,
      insert_text_format: :snippet,
      kind: :class,
      label: label,
      sort_text: boost(label)
    )
  end

  defp to_completion_item(%Result.Macro{name: name} = macro)
       when name not in @snippet_macros do
    label = "#{macro.name}/#{macro.arity}"
    sort_text = String.replace(label, "__", "")
    Completion.Item.new(label: label, kind: :function, detail: macro.spec, sort_text: sort_text)
  end

  defp to_completion_item(_) do
    :skip
  end

  defp boost(text, amount \\ 5)

  defp boost(text, amount) when amount in 0..10 do
    boost_char = ?* - amount
    IO.iodata_to_binary([boost_char, text])
  end

  defp boost(text, _) do
    boost(text, 0)
  end
end
