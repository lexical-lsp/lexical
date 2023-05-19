defmodule Lexical.Server.CodeIntelligence.Completion.Translations.Struct do
  alias Lexical.RemoteControl.Completion.Result
  alias Lexical.Server.CodeIntelligence.Completion.Env
  alias Lexical.Server.CodeIntelligence.Completion.Translatable

  use Translatable.Impl, for: Result.Struct

  def translate(%Result.Struct{} = struct, builder, %Env{} = env) do
    struct_reference? = Env.in_context?(env, :struct_reference)

    add_curlies? = add_curlies?(env)

    insert_text =
      if add_percent?(env) do
        "%" <> struct.name
      else
        struct.name
      end

    builder_opts =
      if struct_reference? do
        [kind: :struct, detail: "#{struct.name} (Struct)", label: "%#{struct.name}"]
      else
        [kind: :module, detail: "#{struct.name} (Module)", label: struct.name]
      end

    if add_curlies? do
      builder.snippet(env, insert_text <> "{$1}", builder_opts)
    else
      builder.plain_text(env, insert_text, builder_opts)
    end
  end

  def add_curlies?(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      not String.contains?(env.suffix, "{")
    else
      false
    end
  end

  def add_percent?(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      # A leading percent is added only if the struct reference is to a top-level struct.
      # If it's for a child struct (e.g. %Types.Range) then adding a percent at "Range"
      # will be syntactically invalid and get us `%Types.%Range{}`

      struct_module_name =
        case Code.Fragment.cursor_context(env.prefix) do
          {:struct, {:dot, {:alias, module_name}, []}} ->
            '#{module_name}.'

          {:struct, module_name} ->
            module_name

          {:dot, {:alias, module_name}, _} ->
            module_name

          _ ->
            ''
        end

      contains_period? =
        struct_module_name
        |> List.to_string()
        |> String.contains?(".")

      not contains_period?
    else
      false
    end
  end

  def struct_details(%Env{} = env) do
    if Env.in_context?(env, :struct_reference) do
      add_curlies? = not String.contains?(env.suffix, "{")

      # A leading percent is added only if the struct reference is to a top-level struct.
      # If it's for a child struct (e.g. %Types.Range) then adding a percent at "Range"
      # will be syntactically invalid and get us `%Types.%Range{}`

      struct_module_name =
        case Code.Fragment.cursor_context(env.prefix) do
          {:struct, {:dot, {:alias, module_name}, []}} ->
            '#{module_name}.'

          {:struct, module_name} ->
            module_name

          {:dot, {:alias, module_name}, _} ->
            module_name

          _ ->
            ''
        end

      contains_period? =
        struct_module_name
        |> List.to_string()
        |> String.contains?(".")

      add_percent? = not contains_period?
      {add_curlies?, add_percent?}
    else
      {false, false}
    end
  end
end
