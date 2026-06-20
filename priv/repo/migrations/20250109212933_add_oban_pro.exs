defmodule Glific.Repo.Migrations.AddObanPro do
  use Ecto.Migration

  # Original: Oban.Pro.Migration.up/down - replaced with vanilla Oban.Migration
  def up, do: Oban.Migration.up(prefix: "global")

  def down, do: Oban.Migration.down(prefix: "global")
end
