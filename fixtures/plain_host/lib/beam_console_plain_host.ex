defmodule BeamConsolePlainHost do
  def snapshot do
    BeamConsole.latest_snapshot()
  end
end
