defmodule Lexical.RemoteControl.Dispatch.Handler do
  defmacro __using__(event_types) do
    quote do
      @behaviour :gen_event
      @event_names unquote(event_types)
                   |> List.wrap()
                   |> MapSet.new(fn
                     :all -> :all
                     event when is_tuple(event) -> elem(event, 0)
                   end)

      def init(arg) do
        {:ok, arg}
      end

      def on(event, state) do
        {:ok, event, state}
      end

      def handle_call(_, state) do
        {:ok, state}
      end

      def handle_info(_, state) do
        {:ok, state}
      end

      def handle_event(event, state) when is_tuple(event) do
        cond do
          MapSet.member?(@event_names, elem(event, 0)) ->
            on(event, state)

          MapSet.member?(@event_names, :all) ->
            on(event, state)

          true ->
            {:ok, state}
        end
      end

      def handle_event(_event, state) do
        {:ok, state}
      end

      # handlers only respond to on or info, not calls.
      defoverridable init: 1, handle_info: 2, on: 2
    end
  end
end
