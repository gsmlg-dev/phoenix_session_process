defmodule Phoenix.SessionProcessTest do
  use ExUnit.Case
  doctest Phoenix.SessionProcess

  test "greets the world" do
    assert Phoenix.SessionProcess.hello() == :world
  end
end
