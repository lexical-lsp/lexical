defmodule Lexical.Debug do
  require Logger

  defmacro timed(label, do: block) do
    if enabled?() do
      quote do
        log_timed(unquote(label), fn -> unquote(block) end)
      end
    else
      block
    end
  end

  def log_timed(label, threshold_ms \\ 1, function) when is_function(function, 0) do
    if enabled?() do
      {elapsed_us, result} = :timer.tc(function)
      elapsed_ms = elapsed_us / 1000

      if elapsed_ms >= threshold_ms do
        Logger.info("#{label} took #{Lexical.Formats.time(elapsed_us)}")
      end

      result
    else
      function.()
    end
  end

  defp enabled? do
    true
  end
end
