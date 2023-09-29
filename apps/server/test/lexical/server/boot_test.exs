defmodule Lexical.Server.BootTest do
  alias Lexical.Server.Boot
  alias Lexical.VM.Versions

  use ExUnit.Case
  use Patch

  describe "detect_errors/0" do
    test "returns empty list when all checks succeed" do
      patch_runtime_versions("1.14.5", "25.0")
      patch_compiled_versions("1.14.5", "25.0")

      assert [] = Boot.detect_errors()
    end

    test "includes error when compiled erlang is too new" do
      patch_runtime_versions("1.14.5", "25.0")
      patch_compiled_versions("1.14.5", "26.1")

      assert [error] = Boot.detect_errors()
      assert error =~ "FATAL: Lexical version check failed"
      assert error =~ "Compiled with: 26.1"
      assert error =~ "Started with:  25.0"
    end

    test "includes error when runtime elixir is incompatible" do
      patch_runtime_versions("1.12.0", "24.3.4")
      patch_compiled_versions("1.13.4", "24.3.4")

      assert [error] = Boot.detect_errors()
      assert error =~ "FATAL: Lexical is not compatible with Elixir 1.12.0"
    end

    test "includes error when runtime erlang is incompatible" do
      patch_runtime_versions("1.13.4", "23.0")
      patch_compiled_versions("1.13.4", "23.0")

      assert [error] = Boot.detect_errors()
      assert error =~ "FATAL: Lexical is not compatible with Erlang/OTP 23.0.0"
    end

    test "includes multiple errors when runtime elixir and erlang are incompatible" do
      patch_runtime_versions("1.15.2", "26.0.0")
      patch_compiled_versions("1.15.6", "26.1")

      assert [elixir_error, erlang_error] = Boot.detect_errors()
      assert elixir_error =~ "FATAL: Lexical is not compatible with Elixir 1.15.2"
      assert erlang_error =~ "FATAL: Lexical is not compatible with Erlang/OTP 26.0.0"
    end
  end

  defp patch_runtime_versions(elixir, erlang) do
    patch(Versions, :elixir_version, elixir)
    patch(Versions, :erlang_version, erlang)
  end

  defp patch_compiled_versions(elixir, erlang) do
    patch(Versions, :code_find_file, fn file -> {:ok, file} end)

    patch(Versions, :read_file, fn file ->
      if String.ends_with?(file, ".elixir") do
        {:ok, elixir}
      else
        {:ok, erlang}
      end
    end)
  end
end
