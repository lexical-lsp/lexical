Benchee.run(
  %{
    "next_id" => fn ->
      Snowflake.next_id()
    end
  },
  profile_after: true
)
