defmodule Lexical.RemoteControl.Dispatch.Handler do
  @moduledoc """
  Defines a handler that selectively receives events emitted from a remote control node.

  ## Usage

  Define a handler, specifying the events to be handled and implementing `on_event/2`:

      defmodule MyHandler do
        alias Lexical.RemoteControl.Api.Messages
        alias Lexical.RemoteControl.Dispatch.Handler

        import Messages

        use Handler, [project_compiled()]

        def on_event(project_compiled(), state) do
          ...do something with the message
          {:ok, state}
        end
      end

    Register the handler with dispatch:

    # The second argument here will be passed to the `init/1` callback
    Lexical.RemoteControl.Dispatch.add_handler(MyHandler, init_arg)

  """
  @type event :: tuple()
  @type handler_state :: term()

  @callback on_event(event(), handler_state) :: {:ok, handler_state} | {:error, any()}
  @callback init(term()) :: {:ok, handler_state()}
  @optional_callbacks init: 1

  defmacro __using__(event_types) do
    event_types = List.wrap(event_types)

    handler_bodies =
      if Enum.member?(event_types, :all) do
        [all_handler()]
      else
        handler_bodies(event_types)
      end

    quote do
      @behaviour unquote(__MODULE__)

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

      unquote_splicing(handler_bodies)

      # handlers only respond to on or info, not calls.
      defoverridable init: 1, handle_info: 2, on: 2
    end
  end

  def handler_bodies(event_types) do
    results =
      Enum.map(event_types, fn {event_name, _, _} ->
        event_handler(event_name)
      end)

    results ++ [ignore_handler()]
  end

  defp event_handler(event_name) do
    quote do
      def handle_event(event, state)
          when is_tuple(event) and elem(event, 0) == unquote(event_name) do
        on_event(event, state)
      end
    end
  end

  defp all_handler do
    quote do
      def handle_event(event, state) do
        on_event(event, state)
      end
    end
  end

  defp ignore_handler do
    quote do
      require Logger

      def handle_event(event, state) do
        Logger.error(
          "Handler in #{inspect(__MODULE__)} got an unexpected event #{inspect(event)}"
        )

        {:ok, state}
      end
    end
  end
end
