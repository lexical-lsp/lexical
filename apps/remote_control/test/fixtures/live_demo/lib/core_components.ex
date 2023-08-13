defmodule LiveDemo.CoreComponents do
  use Phoenix.Component

  def render(assigns) do
    ~H"""
    <div>
      <h1>CoreComponents</h1>
    </div>
    """
  end

  attr :name, :string, default: "World"

  def greet(assigns) do
    ~H"""
    <p>Hello, <%= @name %>!</p>
    """
  end
end
