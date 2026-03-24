defmodule Mix.Tasks.Symphony.Eval.ValidateTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Symphony.Eval.Validate

  @dataset_fixture Path.expand("../../fixtures/eval/dataset_smoke.json", __DIR__)
  @rubric_fixture Path.expand("../../fixtures/eval/rubric_smoke.json", __DIR__)

  setup do
    Mix.Task.reenable("symphony.eval.validate")
    :ok
  end

  test "prints help" do
    output =
      capture_io(fn ->
        Validate.run(["--help"])
      end)

    assert output =~ "mix symphony.eval.validate"
  end

  test "fails on invalid options" do
    assert_raise Mix.Error, ~r/Invalid option/, fn ->
      Validate.run(["--wat"])
    end
  end

  test "fails when dataset option is missing" do
    assert_raise Mix.Error, ~r/Missing required option --dataset/, fn ->
      Validate.run(["--rubric", @rubric_fixture])
    end
  end

  test "prints machine readable validation output" do
    output =
      capture_io(fn ->
        Validate.run(["--dataset", @dataset_fixture, "--rubric", @rubric_fixture])
      end)

    result = Jason.decode!(output)
    assert result["status"] == "ok"
    assert result["case_count"] == 2
    assert result["rubric_item_count"] == 2
  end
end
