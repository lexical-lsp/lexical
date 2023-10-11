defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Macro do
  alias Lexical.Ast.Env
  alias Lexical.Completion.Translatable
  alias Lexical.Document
  alias Lexical.RemoteControl.Completion.Candidate
  alias Lexical.Server.CodeIntelligence.Completion.Translations
  alias Lexical.Server.CodeIntelligence.Completion.Translations.Callable
  alias Lexical.Server.CodeIntelligence.Completion.Translations.Struct

  @snippet_macros ~w(def defp defmacro defmacrop defimpl defmodule defprotocol defguard defguardp defexception test use)

  defimpl Translatable, for: Candidate.Macro do
    def translate(macro, builder, %Env{} = env) do
      Translations.Macro.translate(macro, builder, env)
    end
  end

  def translate(%Candidate.Macro{name: name}, _builder, _env)
      when name in ["__before_compile__", "__using__", "__after_compile__"] do
    :skip
  end

  def translate(%Candidate.Macro{name: "def", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a function)"

    snippet = """
    def ${1:name}($2) do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost(9)
  end

  def translate(%Candidate.Macro{name: "defp", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a private function)"

    snippet = """
    defp ${1:name}($2) do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost(8)
  end

  def translate(%Candidate.Macro{name: "defmodule"} = macro, builder, env) do
    label = "defmodule (Define a module)"
    suggestion = suggest_module_name(env.document)

    snippet = """
    defmodule ${1:#{suggestion}} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost(7)
  end

  def translate(%Candidate.Macro{name: "defmacro", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a macro)"

    snippet = """
    defmacro ${1:name}($2) do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost(6)
  end

  def translate(%Candidate.Macro{name: "defmacrop", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a private macro)"

    snippet = """
    defmacrop ${1:name}($2) do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost(5)
  end

  def translate(%Candidate.Macro{name: "defprotocol"} = macro, builder, env) do
    label = "#{macro.name} (Define a protocol)"

    snippet = """
    defprotocol ${1:protocol name} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defimpl", arity: 3} = macro, builder, env) do
    label = "#{macro.name} (Define a protocol implementation)"

    snippet = """
    defimpl ${1:protocol name}, for: ${2:type} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defoverridable"} = macro, builder, env) do
    label = "#{macro.name} (Mark a function as overridable)"

    snippet = "defoverridable ${1:keyword or behaviour} $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defdelegate", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a delegate function)"

    snippet = "defdelegate ${1:call}, to: ${2:module} $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defguard", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define a guard macro)"

    snippet = "defguard ${1:call} $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defguardp", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define a private guard macro)"

    snippet = "defguardp ${1:call} $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defexception", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define an exception)"

    snippet = "defexception [${1:fields}] $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "defstruct", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define a struct)"

    snippet = "defstruct [${1:fields}] $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "alias", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (alias a module's name)"

    snippet = "alias $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "use", arity: 1}, builder, env) do
    label = "use (invoke another module's __using__ macro)"
    snippet = "use $0"

    env
    |> builder.snippet(snippet,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "require" <> _, arity: 2} = macro, builder, env) do
    label = "#{macro.name} (require a module's macros)"

    snippet = "require $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "quote" <> _, arity: 2} = macro, builder, env) do
    label = "#{macro.name} (quote block)"

    snippet = """
    quote ${1:options} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "receive" <> _, arity: 1} = macro, builder, env) do
    label = "#{macro.name} (receive block)"

    snippet = """
    receive do
      ${1:message shape} -> $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "try" <> _, arity: 1} = macro, builder, env) do
    label = "#{macro.name} (try / catch / rescue block)"

    snippet = """
    try do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "with" <> _, arity: 1} = macro, builder, env) do
    label = "with block"

    snippet = """
    with ${1:match} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "case", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Case statement)"

    snippet = """
    case ${1:test} do
      ${2:match} -> $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "if", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (If statement)"

    snippet = """
    if ${1:test} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "import", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (import a module's functions)"

    snippet = "import $0"

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "unless", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Unless statement)"

    snippet = """
    unless ${1:test} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "cond"} = macro, builder, env) do
    label = "#{macro.name} (Cond statement)"

    snippet = """
    cond do
      ${1:test} ->
        $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: "for"} = macro, builder, env) do
    label = "#{macro.name} (comprehension)"

    snippet = """
    for ${1:match} <- ${2:enumerable} do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: macro.spec,
      kind: :class,
      label: label
    )
    |> builder.boost()
  end

  @stub_label ~S(test "message"           )
  @plain_label ~S(test "message" do...     )
  @context_label ~S(test "message", %{} do...)

  def translate(%Candidate.Macro{name: "test", arity: 1}, builder, env) do
    stub_label = @stub_label

    stub_snippet = ~S(test "${0:message}")

    env
    |> builder.snippet(stub_snippet,
      detail: "A stub test",
      kind: :class,
      label: stub_label
    )
    |> builder.boost(1)
  end

  def translate(%Candidate.Macro{name: "test", arity: 2}, builder, env) do
    plain_label = @plain_label

    plain_snippet = """
    test "${1:message}" do
      $0
    end\
    """

    env
    |> builder.snippet(plain_snippet,
      detail: "A test",
      kind: :class,
      label: plain_label
    )
    |> builder.boost(2)
  end

  def translate(%Candidate.Macro{name: "test", arity: 3}, builder, env) do
    context_label = @context_label

    context_snippet = """
    test "${1:message}", %{${2:context}} do
      $0
    end\
    """

    env
    |> builder.snippet(context_snippet,
      detail: "A test that receives context",
      kind: :class,
      label: context_label
    )
    |> builder.boost(3)
  end

  def translate(%Candidate.Macro{name: "describe"}, builder, env) do
    snippet = """
    describe "${1:message}" do
      $0
    end\
    """

    env
    |> builder.snippet(snippet,
      detail: "A describe block",
      kind: :class,
      label: ~S(describe "message")
    )
    |> builder.boost(1)
  end

  def translate(%Candidate.Macro{name: "__MODULE__"} = macro, builder, env) do
    if Env.in_context?(env, :struct_reference) do
      Struct.completion(env, builder, macro.name, macro.name)
    else
      env
      |> builder.plain_text("__MODULE__",
        detail: macro.spec,
        kind: :constant,
        label: "__MODULE__"
      )
      |> builder.boost()
    end
  end

  def translate(%Candidate.Macro{name: dunder_form} = macro, builder, env)
      when dunder_form in ~w(__CALLER__ __DIR__ __ENV__ __MODULE__ __STACKTRACE__) do
    env
    |> builder.plain_text(dunder_form,
      detail: macro.spec,
      kind: :constant,
      label: dunder_form
    )
    |> builder.boost()
  end

  def translate(%Candidate.Macro{name: dunder_form}, _builder, _env)
      when dunder_form in ~w(__aliases__ __block__) do
    :skip
  end

  def translate(%Candidate.Macro{name: name} = macro, _builder, env)
      when name not in @snippet_macros do
    Callable.completion(macro, env)
  end

  def translate(%Candidate.Macro{}, _builder, _env) do
    :skip
  end

  def suggest_module_name(%Document{} = document) do
    result =
      document.path
      |> Path.split()
      |> Enum.reduce(false, fn
        "lib", _ ->
          {:lib, []}

        "test", _ ->
          {:test, []}

        "support", {:test, _} ->
          {:lib, []}

        _, false ->
          false

        element, {type, elements} ->
          camelized =
            element
            |> Path.rootname()
            |> Macro.camelize()

          {type, [camelized | elements]}
      end)

    case result do
      {_, parts} ->
        parts
        |> Enum.reverse()
        |> Enum.join(".")

      false ->
        document.path
        |> Path.basename()
        |> Path.rootname()
        |> Macro.camelize()
    end
  end
end
