defmodule SymphonyElixir.EvalTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Eval

  @dataset_fixture Path.expand("../fixtures/eval/dataset_smoke.json", __DIR__)
  @rubric_fixture Path.expand("../fixtures/eval/rubric_smoke.json", __DIR__)

  test "validates json dataset and rubric inputs" do
    assert {:ok, result} = Eval.validate_inputs(@dataset_fixture, @rubric_fixture)

    assert result.status == "ok"
    assert result.dataset_version == "DS-SSI-WCP-v1.0.0"
    assert result.rubric_version == "rubric-v0"
    assert result.case_count == 2
    assert result.rubric_item_count == 2
    assert result.prompt_versions == ["PV-BASELINE-001"]
    assert result.rel_gate_ids == ["RG-P0-001"]
    assert result.threshold_ids == ["DS-THRESH-001", "DS-THRESH-006"]
  end

  test "validates yaml inputs" do
    in_temp_dir(fn root ->
      dataset_path = Path.join(root, "dataset.yaml")
      rubric_path = Path.join(root, "rubric.yml")

      File.write!(dataset_path, """
      dataset_version: DS-SSI-WCP-v1.0.0
      cases:
        - dataset_case_id: GD-010
          prompt_version: PV-BASELINE-001
          rel_gate_id: RG-P0-001
          prd_feature_id:
            - FEAT-001
          srs_requirement_id:
            - SRS-009
          app_flow_id: AF-002
          input:
            mission_type: Execute Ready Ticket
      """)

      File.write!(rubric_path, """
      rubric_version: rubric-v0
      items:
        - rubric_item_id: RB-001
          criterion: Carries required identifiers
          threshold_id: DS-THRESH-001
          weight: 1.0
      """)

      assert {:ok, result} = Eval.validate_inputs(dataset_path, rubric_path)
      assert result.case_count == 1
      assert result.rubric_item_count == 1
    end)
  end

  test "returns an error for duplicate dataset ids" do
    in_temp_dir(fn root ->
      dataset_path = Path.join(root, "dataset.json")

      File.write!(dataset_path, """
      {
        "dataset_version": "DS-SSI-WCP-v1.0.0",
        "cases": [
          {
            "dataset_case_id": "GD-001",
            "prompt_version": "PV-BASELINE-001",
            "rel_gate_id": "RG-P0-001",
            "prd_feature_id": "FEAT-001",
            "srs_requirement_id": "SRS-009",
            "app_flow_id": "AF-002",
            "input": {}
          },
          {
            "dataset_case_id": "GD-001",
            "prompt_version": "PV-BASELINE-001",
            "rel_gate_id": "RG-P0-001",
            "prd_feature_id": "FEAT-001",
            "srs_requirement_id": "SRS-009",
            "app_flow_id": "AF-002",
            "input": {}
          }
        ]
      }
      """)

      assert {:error, "duplicate dataset_case_id"} = Eval.validate_inputs(dataset_path, @rubric_fixture)
    end)
  end

  test "returns an error when reference scores mention an unknown rubric item" do
    in_temp_dir(fn root ->
      dataset_path = Path.join(root, "dataset.json")

      File.write!(dataset_path, """
      {
        "dataset_version": "DS-SSI-WCP-v1.0.0",
        "cases": [
          {
            "dataset_case_id": "GD-001",
            "prompt_version": "PV-BASELINE-001",
            "rel_gate_id": "RG-P0-001",
            "prd_feature_id": "FEAT-001",
            "srs_requirement_id": "SRS-009",
            "app_flow_id": "AF-002",
            "input": {},
            "reference_scores": {
              "RB-999": 1.0
            }
          }
        ]
      }
      """)

      assert {:error, "invalid reference_scores for dataset_case_id GD-001"} =
               Eval.validate_inputs(dataset_path, @rubric_fixture)
    end)
  end

  test "runs the smoke path and writes manifest, summary, and case artifacts" do
    in_temp_dir(fn root ->
      output_dir = Path.join(root, "tmp/evals/T-EVAL-001")

      assert {:ok, result} =
               Eval.run(
                 @dataset_fixture,
                 @rubric_fixture,
                 output_dir,
                 "T-EVAL-001",
                 "RG-P0-001",
                 smoke: true
               )

      assert result.status == "ok"
      assert result.smoke
      assert File.regular?(result.manifest_path)
      assert File.regular?(result.summary_path)

      manifest = read_json!(result.manifest_path)
      summary = read_json!(result.summary_path)
      case_files = Path.wildcard(Path.join([output_dir, "cases", "*.json"])) |> Enum.sort()

      assert manifest["eval_id"] == "T-EVAL-001"
      assert manifest["rel_gate_id"] == "RG-P0-001"
      assert manifest["dataset_version"] == "DS-SSI-WCP-v1.0.0"
      assert manifest["rubric_version"] == "rubric-v0"
      assert manifest["smoke"] == true
      assert summary["case_count"] == 2
      assert summary["completed_case_count"] == 2
      assert length(case_files) == 2
    end)
  end

  test "runs the full path and keeps all cases" do
    in_temp_dir(fn root ->
      output_dir = Path.join(root, "tmp/evals/EVAL-001")

      assert {:ok, result} =
               Eval.run(
                 @dataset_fixture,
                 @rubric_fixture,
                 output_dir,
                 "EVAL-001",
                 "RG-P0-001"
               )

      summary = read_json!(result.summary_path)
      assert summary["smoke"] == false
      assert summary["case_count"] == 2
      assert summary["average_score"] > 0.0
    end)
  end

  test "returns an error when rel gate id does not match dataset cases" do
    in_temp_dir(fn root ->
      output_dir = Path.join(root, "tmp/evals/EVAL-001")

      assert {:error, "dataset rel_gate_id values do not match requested rel_gate_id RG-P9-999"} =
               Eval.run(
                 @dataset_fixture,
                 @rubric_fixture,
                 output_dir,
                 "EVAL-001",
                 "RG-P9-999"
               )
    end)
  end

  test "returns an error when a selected case is missing a required rubric score" do
    in_temp_dir(fn root ->
      dataset_path = Path.join(root, "dataset.json")
      output_dir = Path.join(root, "tmp/evals/EVAL-001")

      File.write!(dataset_path, """
      {
        "dataset_version": "DS-SSI-WCP-v1.0.0",
        "cases": [
          {
            "dataset_case_id": "GD-001",
            "prompt_version": "PV-BASELINE-001",
            "rel_gate_id": "RG-P0-001",
            "prd_feature_id": "FEAT-001",
            "srs_requirement_id": "SRS-009",
            "app_flow_id": "AF-002",
            "input": {},
            "reference_scores": {
              "RB-001": 1.0
            }
          }
        ]
      }
      """)

      assert {:error, "dataset_case_id GD-001 is missing one or more rubric reference scores"} =
               Eval.run(
                 dataset_path,
                 @rubric_fixture,
                 output_dir,
                 "EVAL-001",
                 "RG-P0-001"
               )
    end)
  end

  defp in_temp_dir(fun) do
    root =
      Path.join(System.tmp_dir!(), "symphony-eval-test-#{System.unique_integer([:positive, :monotonic])}")

    File.rm_rf!(root)
    File.mkdir_p!(root)

    try do
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
