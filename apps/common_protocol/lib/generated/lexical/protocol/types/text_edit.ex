# This file's contents are auto-generated. Do not edit.
defmodule Lexical.Protocol.Types.TextEdit do
  alias Lexical.Protocol.Proto
  alias Lexical.Protocol.Types
  use Proto
  deftype new_text: string(), range: Types.Range

  # How to add this function to this module without editing this file?
  # it is important for RemoteControl.namespace_struct()
  def cast_from_rpc(struct) do
    map = Map.from_struct(struct)
    range_map = Map.from_struct(map.range)
    position_end_map = Map.from_struct(range_map.end)
    position_start_map = Map.from_struct(range_map.start)
    position_end = struct(Types.Position, position_end_map)
    position_start = struct(Types.Position, position_start_map)
    range_map = Map.put(range_map, :end, position_end)
    range_map = Map.put(range_map, :start, position_start)
    range = struct(Types.Range, range_map)
    map = Map.put(map, :range, range)
    text_edit = struct(__MODULE__, map)
    text_edit
  end
end
