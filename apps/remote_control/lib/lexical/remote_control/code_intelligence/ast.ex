defmodule Lexical.RemoteControl.CodeIntelligence.Ast do
  alias Lexical.Document
  alias Lexical.Document.Position
  alias Lexical.RemoteControl.CodeMod.Ast.Aliases

  require Logger

  @doc """
  Expands the aliases in the given `document`, `postion` and `module_aliases`.

  When we refer to a module, it's usually a short name,
  so it's probably aliased or in a nested module,
  so we need to find the real full name of the module at the cursor position.

  For example, if we have:

    ```elixir
    defmodule Project do
      defmodule Issue do
        defstruct [:message]
      end

      def message(%Issue{|} = issue) do # cursor marked as `|`
      end
    end
    ```

  Then the the expanded module is `Project.Issue`.

  Another example:

    ```elixir
    defmodule Project do
      defmodule Issue do
        defstruct [:message]
      end
    end

    defmodule MyModule do
      alias Project, as: MyProject

      def message(%MyProject.Issue{|} = issue) do
      end
    end
    ```

  Then the the expanded module is still `Project.Issue`.

  And sometimes we can't find the full name by the `Aliases.at/2` function,
  then we just return the `Module.concat(module_aliases)` as it is.
  """
  @type short_alias :: atom()
  @type module_aliases :: [short_alias]

  @spec expand_aliases(
          document :: Document.t(),
          position :: Position.t(),
          module_aliases :: module_aliases()
        ) :: {:ok, module()} | :error
  def expand_aliases(%Document{} = document, %Position{} = position, module_aliases)
      when is_list(module_aliases) do
    [first | rest] = module_aliases

    with {:ok, aliases_mapping} <- Aliases.at(document, position),
         {:ok, from} <- Map.fetch(aliases_mapping, first) do
      {:ok, Module.concat([from | rest])}
    else
      _ ->
        {:ok, Module.concat(module_aliases)}
    end
  end

  def expand_aliases(_, _, nil) do
    Logger.warning("Aliases are nil, can't expand them")
    :error
  end
end
