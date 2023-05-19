defmodule Lexical.ThrottlerTest do
  alias Lexical.Throttler
  use ExUnit.Case

  setup do
    start_supervised!(Throttler)
    :ok
  end

  test "it should run the job when state is initialized" do
    test_pid = self()

    job_func = fn -> send(test_pid, :done) end
    job_info = Throttler.JobInfo.new(job_func, :test, 100)
    Throttler.run(job_info)

    assert_receive :done, 100 + 10
  end

  test "it should run the job when the interval has ended" do
    test_pid = self()

    job_func = fn -> send(test_pid, :done) end
    job_info = Throttler.JobInfo.new(job_func, :test, 100)

    Throttler.run(job_info)
    Process.sleep(100 + 10)
    Throttler.run(job_info)

    assert_receive :done, 100 + 10
    assert_receive :done, 100 + 10
  end

  test "it should ignore the second job when the interval has not ended" do
    test_pid = self()

    job_func = fn -> send(test_pid, :done) end
    job_info = Throttler.JobInfo.new(job_func, :test, 100)

    Throttler.run(job_info)
    Process.sleep(100 - 10)
    Throttler.run(job_info)

    assert_receive :done, 100 + 10
    refute_receive :done, 100 + 10
  end
end
