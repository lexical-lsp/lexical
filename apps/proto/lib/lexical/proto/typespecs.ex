defmodule Lexical.Proto.Typespecs do
  alias Lexical.Proto.CompileMetadata

  defmacro __using__(opts) do
    group_name = Keyword.fetch!(opts, :for)

    quote do
      unquote(for_group(group_name))
    end
  end

  defp for_group(group_name) do
    modules =
      case group_name do
        :notifications -> CompileMetadata.notification_modules()
        :requests -> CompileMetadata.request_modules()
        :responses -> CompileMetadata.response_modules()
        :types -> CompileMetadata.type_modules()
      end

    quote do
      unquote(build_typespec(singular(group_name), modules))
    end
  end

  def build_typespec(type_name, modules) do
    spec_name = {type_name, [], nil}

    spec =
      Enum.reduce(modules, nil, fn
        module, nil ->
          quote do
            unquote(module).t()
          end

        module, spec ->
          quote do
            unquote(module).t() | unquote(spec)
          end
      end)

    quote do
      @type unquote(spec_name) :: unquote(spec)
    end
  end

  defp singular(atom) when is_atom(atom) do
    atom |> Atom.to_string() |> singular() |> String.to_atom()
  end

  defp singular(s) when is_binary(s) do
    String.replace(s, ~r/(\w+)+s/, "\\1")
  end
end
