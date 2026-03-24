defmodule Mix.Tasks.Symphony.Eval.RunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Symphony.Eval.Run

  @dataset_fixture Path.expand("../../fixtures/eval/dataset_smoke.json", __DIR__)
  @rubric_fixture Path.expand("../../fixtures/eval/rubric_smoke.json", __DIR__)

  setup do
    Mix.Task.reenable("symphony.eval.run")
    :ok
  end

  test "prints help" do
    output =
      capture_io(fn ->
        Run.run(["--help"])
      end)

    assert output =~ "mix symphony.eval.run"
  end

  test "fails on invalid options" do
    assert_raise Mix.Error, ~r/Invalid option/, fn ->
      Run.run(["--wat"])
    end
  end

  test "fails when eval id is missing" do
    assert_raise Mix.Error, ~r/Missing required option --eval-id/, fn ->
      Run.run([
        "--dataset",
        @dataset_fixture,
        "--rubric",
        @rubric_fixture,
        "--output-dir",
        "tmp/evals/EVAL-001",
        "--rel-gate-id",
        "RG-P0-001"
      ])
    end
  end

  test "runs the smoke path and prints machine readable output" do
    in_temp_dir(fn root ->
      output_dir = Path.join(root, "tmp/evals/T-EVAL-001")

      output =
        capture_io(fn ->
          Run.run([
            "--dataset",
            @dataset_fixture,
            "--rubric",
            @rubric_fixture,
            "--output-dir",
            output_dir,
            "--eval-id",
            "T-EVAL-001",
            "--rel-gate-id",
            "RG-P0-001",
            "--smoke"
          ])
        end)

      result = Jason.decode!(output)
      assert result["status"] == "ok"
      assert result["smoke"] == true
      assert File.regular?(result["manifest_path"])
      assert File.regular?(result["summary_path"])
    end)
  end

  defp in_temp_dir(fun) do
    root =
      Path.join(System.tmp_dir!(), "symphony-eval-task-test-#{System.unique_integer([:positive, :monotonic])}")

    File.rm_rf!(root)
    File.mkdir_p!(root)

    try do
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end
end
