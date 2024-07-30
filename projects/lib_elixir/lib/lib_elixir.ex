defmodule LibElixir do
  @moduledoc """
  Installs a specified version of the Elixir standard library in your module.
  """

  defmacro __using__(opts) do
    namespace = __CALLER__.module
    ref = Keyword.fetch!(opts, :ref)
    otp_app = Keyword.fetch!(opts, :otp_app)

    Module.register_attribute(namespace, :lib_elixir_ref, persist: true)
    Module.put_attribute(namespace, :lib_elixir_ref, ref)

    quote do
      @on_load :__lib_elixir__

      def __lib_elixir__ do
        # remove old module in case it was loaded before lib_elixir compiled
        :code.purge(__MODULE__)

        app = unquote(otp_app)
        lib_elixir_app = LibElixir.Namespace.app_name(__MODULE__)

        lib_elixir_code_path =
          [:code.lib_dir(app), "..", to_string(lib_elixir_app), "ebin"]
          |> Path.join()
          |> Path.expand()

        :code.add_patha(~c"#{lib_elixir_code_path}")

        :ok
      end
    end
  end

  @doc false
  def fetch_ref(module) do
    if function_exported?(module, :__info__, 1) do
      Keyword.fetch(module.__info__(:attributes), :lib_elixir_ref)
    else
      :error
    end
  end
end
