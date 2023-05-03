defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Macro do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Macro

  @snippet_macros ~w(def defp defmacro defmacrop defimpl defmodule defprotocol defguard defguardp defexception)

  def translate(%Result.Macro{name: name}, _builder, _env)
      when name in ["__before_compile__", "__using__", "__after_compile__"] do
    :skip
  end

  def translate(%Result.Macro{name: "def", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a function)"

    snippet = """
    def ${1:name}($2) do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label, 10)
    )
  end

  def translate(%Result.Macro{name: "defp", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a private function)"

    snippet = """
    defp ${1:name}($2) do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label, 9)
    )
  end

  def translate(%Result.Macro{name: "defmodule"} = macro, builder, env) do
    label = "defmodule (Define a module)"

    snippet = """
    defmodule ${1:module name} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label, 8)
    )
  end

  def translate(%Result.Macro{name: "defmacro", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a macro)"

    snippet = """
    defmacro ${1:name}($2) do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label, 7)
    )
  end

  def translate(%Result.Macro{name: "defmacrop", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a private macro)"

    snippet = """
    defmacrop ${1:name}($2) do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label, 6)
    )
  end

  def translate(%Result.Macro{name: "defprotocol"} = macro, builder, env) do
    label = "#{macro.name} (Define a protocol)"

    snippet = """
    defprotocol ${1:protocol name} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defimpl", arity: 3} = macro, builder, env) do
    label = "#{macro.name} (Define a protocol implementation)"

    snippet = """
    defimpl ${1:protocol name}, for: ${2:type} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defoverridable"} = macro, builder, env) do
    label = "#{macro.name} (Mark a function as overridable)"

    snippet = "defoverridable ${1:keyword or behaviour} $0"

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defdelegate", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Define a delegate function)"

    snippet = """
    defdelegate ${1:call}, to: ${2:module} $0
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defguard", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define a guard macro)"

    snippet = """
    defguard ${1:call} $0
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defguardp", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define a private guard macro)"

    snippet = """
    defguardp ${1:call} $0
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defexception", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define an exception)"

    snippet = """
    defexception [${1:fields}] $0
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "defstruct", arity: 1} = macro, builder, env) do
    label = "#{macro.name} (Define a struct)"

    snippet = """
    defstruct [${1:fields}] $0
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "alias", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (alias a module's name)"

    snippet = "alias $0"

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "require" <> _, arity: 2} = macro, builder, env) do
    label = "#{macro.name} (require a module's macros)"

    snippet = "require $0"

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "quote" <> _, arity: 2} = macro, builder, env) do
    label = "#{macro.name} (quote block)"

    snippet = """
    quote ${1:options} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "receive" <> _, arity: 1} = macro, builder, env) do
    label = "#{macro.name} (receive block)"

    snippet = """
    receive do
      ${1:message shape} -> $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "try" <> _, arity: 1} = macro, builder, env) do
    label = "#{macro.name} (try / catch / rescue block)"

    snippet = """
    try do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "with" <> _, arity: 1} = macro, builder, env) do
    label = "with block"

    snippet = """
    with ${1:match} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "case", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Case statement)"

    snippet = """
    case ${1:test} do
      ${2:match} -> $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "if", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (If statement)"

    snippet = """
    if ${1:test} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "import", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (import a module's functions)"

    snippet = "import $0"

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "unless", arity: 2} = macro, builder, env) do
    label = "#{macro.name} (Unless statement)"

    snippet = """
    unless ${1:test} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "cond"} = macro, builder, env) do
    label = "#{macro.name} (Cond statement)"

    snippet = """
    cond do
      ${1:test} ->
        $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "for"} = macro, builder, env) do
    label = "#{macro.name} (comprehension)"

    snippet = """
    for ${1:match} <- ${2:enumerable} do
      $0
    end
    """

    builder.snippet(env, snippet,
      detail: macro.spec,
      kind: :class,
      label: label,
      sort_text: builder.boost(label)
    )
  end

  def translate(%Result.Macro{name: "__MODULE__"} = macro, builder, env) do
    if Env.struct_reference?(env) do
      builder.snippet(env, "%__MODULE__{$1}",
        detail: "%__MODULE__{}",
        label: "%__MODULE__{}",
        kind: :struct
      )
    else
      builder.plain_text(env, "__MODULE__",
        detail: macro.spec,
        kind: :constant,
        label: "__MODULE__",
        sort_text: builder.boost("__MODULE__")
      )
    end
  end

  def translate(%Result.Macro{name: dunder_form} = macro, builder, env)
      when dunder_form in ~w(__CALLER__ __DIR__ __ENV__ __MODULE__ __STACKTRACE__) do
    builder.plain_text(env, dunder_form,
      detail: macro.spec,
      kind: :constant,
      label: dunder_form,
      sort_text: builder.boost(dunder_form)
    )
  end

  def translate(%Result.Macro{name: dunder_form}, _builder, _env)
      when dunder_form in ~w(__aliases__ __block__) do
    :skip
  end

  def translate(%Result.Macro{name: name} = macro, builder, env)
      when name not in @snippet_macros do
    label = "#{macro.name}/#{macro.arity}"
    sort_text = String.replace(label, "__", "")

    builder.plain_text(env, label,
      detail: macro.spec,
      kind: :function,
      sort_text: sort_text,
      label: label
    )
  end

  def translate(%Result.Macro{}, _builder, _env) do
    :skip
  end
end
