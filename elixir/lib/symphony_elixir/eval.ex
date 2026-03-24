defmodule SymphonyElixir.Eval do
  @moduledoc false

  @smoke_case_limit 3

  @type dataset_case :: map()
  @type dataset :: %{
          required(String.t()) => term(),
          optional(String.t()) => term()
        }
  @type rubric_item :: map()
  @type rubric :: %{
          required(String.t()) => term(),
          optional(String.t()) => term()
        }
  @type validation_result :: %{
          status: String.t(),
          dataset_path: String.t(),
          rubric_path: String.t(),
          dataset_version: String.t(),
          rubric_version: String.t(),
          case_count: non_neg_integer(),
          rubric_item_count: non_neg_integer(),
          prompt_versions: [String.t()],
          rel_gate_ids: [String.t()],
          threshold_ids: [String.t()]
        }
  @type run_result :: %{
          status: String.t(),
          smoke: boolean(),
          output_dir: String.t(),
          manifest_path: String.t(),
          summary_path: String.t(),
          manifest: map(),
          summary: map()
        }

  @spec validate_inputs(Path.t(), Path.t()) :: {:ok, validation_result()} | {:error, String.t()}
  def validate_inputs(dataset_path, rubric_path) do
    expanded_dataset_path = Path.expand(dataset_path)
    expanded_rubric_path = Path.expand(rubric_path)

    with {:ok, dataset, rubric} <- load_inputs(expanded_dataset_path, expanded_rubric_path) do
      {:ok,
       %{
         status: "ok",
         dataset_path: expanded_dataset_path,
         rubric_path: expanded_rubric_path,
         dataset_version: dataset["dataset_version"],
         rubric_version: rubric["rubric_version"],
         case_count: length(dataset["cases"]),
         rubric_item_count: length(rubric["items"]),
         prompt_versions: dataset |> case_values("prompt_version") |> Enum.sort(),
         rel_gate_ids: dataset |> case_values("rel_gate_id") |> Enum.sort(),
         threshold_ids: rubric |> rubric_threshold_ids() |> Enum.sort()
       }}
    end
  end

  @spec run(Path.t(), Path.t(), Path.t(), String.t(), String.t(), keyword()) ::
          {:ok, run_result()} | {:error, String.t()}
  def run(dataset_path, rubric_path, output_dir, eval_id, rel_gate_id, opts \\ []) do
    smoke? = Keyword.get(opts, :smoke, false)
    expanded_output_dir = Path.expand(output_dir)

    with {:ok, dataset, rubric} <- load_inputs(Path.expand(dataset_path), Path.expand(rubric_path)),
         :ok <- ensure_eval_id(eval_id),
         :ok <- ensure_rel_gate_id(rel_gate_id),
         :ok <- ensure_rel_gate_match(dataset, rel_gate_id),
         selected_cases <- select_cases(dataset["cases"], smoke?),
         :ok <- ensure_cases_have_scores(selected_cases, rubric["items"]),
         {:ok, output_paths} <- prepare_output_paths(expanded_output_dir),
         {:ok, report} <-
           build_report(
             selected_cases,
             dataset["dataset_version"],
             rubric["items"],
             rubric["rubric_version"],
             eval_id,
             rel_gate_id,
             smoke?
           ),
         :ok <- write_report(output_paths, report, dataset, rubric) do
      {:ok,
       %{
         status: "ok",
         smoke: smoke?,
         output_dir: expanded_output_dir,
         manifest_path: output_paths.manifest_path,
         summary_path: output_paths.summary_path,
         manifest: report.manifest,
         summary: report.summary
       }}
    end
  end

  @spec load_inputs(Path.t(), Path.t()) :: {:ok, dataset(), rubric()} | {:error, String.t()}
  defp load_inputs(dataset_path, rubric_path) do
    with {:ok, dataset} <- load_file(dataset_path, "dataset"),
         :ok <- validate_dataset(dataset),
         {:ok, rubric} <- load_file(rubric_path, "rubric"),
         :ok <- validate_rubric(rubric),
         :ok <- ensure_reference_scores_shape(dataset, rubric) do
      {:ok, dataset, rubric}
    end
  end

  @spec load_file(Path.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  defp load_file(path, label) do
    with :ok <- ensure_file_exists(path, label),
         {:ok, decoded} <- decode_file(path, label),
         true <- is_map(decoded) or {:error, "#{label} file must decode to a map: #{path}"} do
      {:ok, normalize_keys(decoded)}
    end
  end

  @spec ensure_file_exists(Path.t(), String.t()) :: :ok | {:error, String.t()}
  defp ensure_file_exists(path, label) do
    if File.regular?(path) do
      :ok
    else
      {:error, "#{label} file not found: #{path}"}
    end
  end

  @spec decode_file(Path.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  defp decode_file(path, label) do
    case File.read(path) do
      {:ok, content} ->
        decode_content(content, Path.extname(path), path, label)

      {:error, reason} ->
        {:error, "Unable to read #{label} file #{path}: #{inspect(reason)}"}
    end
  end

  @spec decode_content(String.t(), String.t(), Path.t(), String.t()) ::
          {:ok, term()} | {:error, String.t()}
  defp decode_content(content, extension, path, label) do
    case extension do
      ".json" ->
        case Jason.decode(content) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, reason} -> {:error, "Unable to decode #{label} JSON #{path}: #{Exception.message(reason)}"}
        end

      ".yaml" ->
        decode_yaml(content, path, label)

      ".yml" ->
        decode_yaml(content, path, label)

      _ ->
        {:error, "#{label} file must use .json, .yaml, or .yml: #{path}"}
    end
  end

  @spec decode_yaml(String.t(), Path.t(), String.t()) :: {:ok, term()} | {:error, String.t()}
  defp decode_yaml(content, path, label) do
    case YamlElixir.read_from_string(content) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, reason} -> {:error, "Unable to decode #{label} YAML #{path}: #{inspect(reason)}"}
    end
  end

  @spec validate_dataset(dataset()) :: :ok | {:error, String.t()}
  defp validate_dataset(dataset) do
    with :ok <- require_non_empty_string(dataset, "dataset_version", "dataset_version"),
         {:ok, cases} <- fetch_non_empty_list(dataset, "cases", "dataset cases"),
         :ok <- ensure_unique_case_ids(cases) do
      reduce_until_error(cases, &validate_case/1)
    end
  end

  @spec validate_case(dataset_case()) :: :ok | {:error, String.t()}
  defp validate_case(dataset_case) when is_map(dataset_case) do
    [
      require_non_empty_string(dataset_case, "dataset_case_id", "dataset_case_id"),
      require_non_empty_string(dataset_case, "prompt_version", "prompt_version"),
      require_non_empty_string(dataset_case, "rel_gate_id", "rel_gate_id"),
      require_string_or_string_list(dataset_case, "prd_feature_id"),
      require_string_or_string_list(dataset_case, "srs_requirement_id"),
      require_string_or_string_list(dataset_case, "app_flow_id"),
      require_present(dataset_case, "input", "input")
    ]
    |> first_error()
  end

  defp validate_case(_dataset_case), do: {:error, "dataset case entries must be maps"}

  @spec validate_rubric(rubric()) :: :ok | {:error, String.t()}
  defp validate_rubric(rubric) do
    with :ok <- require_non_empty_string(rubric, "rubric_version", "rubric_version"),
         {:ok, items} <- fetch_non_empty_list(rubric, "items", "rubric items"),
         :ok <- ensure_unique_item_ids(items) do
      reduce_until_error(items, &validate_rubric_item/1)
    end
  end

  @spec validate_rubric_item(rubric_item()) :: :ok | {:error, String.t()}
  defp validate_rubric_item(item) when is_map(item) do
    [
      require_non_empty_string(item, "rubric_item_id", "rubric_item_id"),
      require_non_empty_string(item, "criterion", "criterion"),
      require_non_empty_string(item, "threshold_id", "threshold_id"),
      require_positive_number(item, "weight")
    ]
    |> first_error()
  end

  defp validate_rubric_item(_item), do: {:error, "rubric items must be maps"}

  @spec require_non_empty_string(map(), String.t(), String.t()) :: :ok | {:error, String.t()}
  defp require_non_empty_string(map, key, label) do
    case Map.get(map, key) do
      value ->
        if present_string?(value) do
          :ok
        else
          {:error, "missing or invalid #{label}"}
        end
    end
  end

  @spec require_present(map(), String.t(), String.t()) :: :ok | {:error, String.t()}
  defp require_present(map, key, label) do
    if Map.has_key?(map, key) and not is_nil(Map.get(map, key)) do
      :ok
    else
      {:error, "missing #{label}"}
    end
  end

  @spec require_string_or_string_list(map(), String.t()) :: :ok | {:error, String.t()}
  defp require_string_or_string_list(map, key) do
    case Map.get(map, key) do
      value when is_binary(value) ->
        if present_string?(value), do: :ok, else: {:error, "missing or invalid #{key}"}

      value when is_list(value) ->
        if Enum.all?(value, &present_string?/1) and value != [] do
          :ok
        else
          {:error, "missing or invalid #{key}"}
        end

      _ ->
        {:error, "missing or invalid #{key}"}
    end
  end

  @spec require_positive_number(map(), String.t()) :: :ok | {:error, String.t()}
  defp require_positive_number(map, key) do
    case Map.get(map, key) do
      value when is_integer(value) and value > 0 -> :ok
      value when is_float(value) and value > 0.0 -> :ok
      _ -> {:error, "missing or invalid #{key}"}
    end
  end

  @spec fetch_non_empty_list(map(), String.t(), String.t()) :: {:ok, [term()]} | {:error, String.t()}
  defp fetch_non_empty_list(map, key, label) do
    case Map.get(map, key) do
      list when is_list(list) and list != [] -> {:ok, list}
      _ -> {:error, "missing or invalid #{label}"}
    end
  end

  @spec ensure_unique_case_ids([dataset_case()]) :: :ok | {:error, String.t()}
  defp ensure_unique_case_ids(cases) do
    ensure_unique_ids(cases, "dataset_case_id", "duplicate dataset_case_id")
  end

  @spec ensure_unique_item_ids([rubric_item()]) :: :ok | {:error, String.t()}
  defp ensure_unique_item_ids(items) do
    ensure_unique_ids(items, "rubric_item_id", "duplicate rubric_item_id")
  end

  @spec ensure_unique_ids([map()], String.t(), String.t()) :: :ok | {:error, String.t()}
  defp ensure_unique_ids(entries, key, message) do
    ids =
      entries
      |> Enum.filter(&is_map/1)
      |> Enum.map(&Map.get(&1, key))
      |> Enum.reject(&is_nil/1)

    if length(ids) == length(Enum.uniq(ids)) do
      :ok
    else
      {:error, message}
    end
  end

  @spec ensure_reference_scores_shape(dataset(), rubric()) :: :ok | {:error, String.t()}
  defp ensure_reference_scores_shape(dataset, rubric) do
    valid_item_ids = rubric_item_ids(rubric["items"]) |> MapSet.new()

    reduce_until_error(dataset["cases"], &validate_reference_scores(&1, valid_item_ids))
  end

  @spec ensure_eval_id(String.t()) :: :ok | {:error, String.t()}
  defp ensure_eval_id(eval_id) do
    if present_string?(eval_id), do: :ok, else: {:error, "eval_id must be a non-empty string"}
  end

  @spec ensure_rel_gate_id(String.t()) :: :ok | {:error, String.t()}
  defp ensure_rel_gate_id(rel_gate_id) do
    if present_string?(rel_gate_id), do: :ok, else: {:error, "rel_gate_id must be a non-empty string"}
  end

  @spec ensure_rel_gate_match(dataset(), String.t()) :: :ok | {:error, String.t()}
  defp ensure_rel_gate_match(dataset, rel_gate_id) do
    dataset_rel_gate_ids = case_values(dataset, "rel_gate_id")

    if Enum.all?(dataset_rel_gate_ids, &(&1 == rel_gate_id)) do
      :ok
    else
      {:error, "dataset rel_gate_id values do not match requested rel_gate_id #{rel_gate_id}"}
    end
  end

  @spec select_cases([dataset_case()], boolean()) :: [dataset_case()]
  defp select_cases(cases, true), do: Enum.take(cases, @smoke_case_limit)
  defp select_cases(cases, false), do: cases

  @spec ensure_cases_have_scores([dataset_case()], [rubric_item()]) :: :ok | {:error, String.t()}
  defp ensure_cases_have_scores(cases, rubric_items) do
    required_ids = rubric_item_ids(rubric_items)

    Enum.reduce_while(cases, :ok, fn dataset_case, :ok ->
      reference_scores = normalize_keys(Map.get(dataset_case, "reference_scores", %{}))

      if Enum.all?(required_ids, &Map.has_key?(reference_scores, &1)) do
        {:cont, :ok}
      else
        {:halt, {:error, "dataset_case_id #{dataset_case["dataset_case_id"]} is missing one or more rubric reference scores"}}
      end
    end)
  end

  @spec prepare_output_paths(Path.t()) ::
          {:ok, %{manifest_path: String.t(), summary_path: String.t(), cases_dir: String.t()}}
  defp prepare_output_paths(output_dir) do
    case File.rm_rf(output_dir) do
      {:error, reason, _path} ->
        {:error, "unable to clear output directory #{output_dir}: #{inspect(reason)}"}

      _ ->
        cases_dir = Path.join(output_dir, "cases")
        :ok = File.mkdir_p!(cases_dir)

        {:ok,
         %{
           manifest_path: Path.join(output_dir, "manifest.json"),
           summary_path: Path.join(output_dir, "summary.json"),
           cases_dir: cases_dir
         }}
    end
  end

  @spec build_report([dataset_case()], String.t(), [rubric_item()], String.t(), String.t(), String.t(), boolean()) ::
          {:ok, %{manifest: map(), summary: map(), case_reports: [map()]}}
  defp build_report(cases, dataset_version, rubric_items, rubric_version, eval_id, rel_gate_id, smoke?) do
    started_at = now_iso8601()

    case_reports =
      Enum.map(cases, fn dataset_case ->
        build_case_report(dataset_case, rubric_items)
      end)

    manifest =
      %{
        eval_id: eval_id,
        run_id: unique_id("run"),
        trace_id: unique_id("trace"),
        prompt_version: case_reports |> Enum.map(& &1["prompt_version"]) |> Enum.uniq() |> unique_summary_value(),
        prompt_versions: case_reports |> Enum.map(& &1["prompt_version"]) |> Enum.uniq() |> Enum.sort(),
        rel_gate_id: rel_gate_id,
        dataset_version: dataset_version,
        rubric_version: rubric_version,
        case_count: length(case_reports),
        smoke: smoke?,
        generated_at: started_at
      }

    summary =
      %{
        status: "completed",
        eval_id: eval_id,
        rel_gate_id: rel_gate_id,
        smoke: smoke?,
        case_count: length(case_reports),
        completed_case_count: length(case_reports),
        average_score: average_score(case_reports),
        dataset_case_ids: Enum.map(case_reports, & &1["dataset_case_id"]),
        generated_at: started_at
      }

    {:ok, %{manifest: manifest, summary: summary, case_reports: case_reports}}
  end

  @spec build_case_report(dataset_case(), [rubric_item()]) :: map()
  defp build_case_report(dataset_case, rubric_items) do
    reference_scores = normalize_keys(Map.fetch!(dataset_case, "reference_scores"))

    rubric_scores =
      Enum.into(rubric_items, %{}, fn item ->
        rubric_item_id = item["rubric_item_id"]
        {rubric_item_id, reference_scores[rubric_item_id]}
      end)

    %{
      "dataset_case_id" => dataset_case["dataset_case_id"],
      "prompt_version" => dataset_case["prompt_version"],
      "rel_gate_id" => dataset_case["rel_gate_id"],
      "status" => "completed",
      "score" => weighted_score(rubric_items, rubric_scores),
      "rubric_scores" => rubric_scores,
      "trace_id" => unique_id("case-trace"),
      "input_digest" => digest(dataset_case["input"])
    }
  end

  @spec write_report(map(), map(), dataset(), rubric()) :: :ok | {:error, String.t()}
  defp write_report(output_paths, report, dataset, rubric) do
    manifest =
      report.manifest
      |> Map.put(:dataset_version, dataset["dataset_version"])
      |> Map.put(:rubric_version, rubric["rubric_version"])

    summary = report.summary

    with :ok <- write_json(output_paths.manifest_path, manifest),
         :ok <- write_json(output_paths.summary_path, summary) do
      write_case_reports(output_paths.cases_dir, report.case_reports)
    end
  end

  @spec write_json(Path.t(), map()) :: :ok | {:error, String.t()}
  defp write_json(path, payload) do
    encoded = Jason.encode_to_iodata!(payload, pretty: true)

    case File.write(path, encoded) do
      :ok -> :ok
      {:error, reason} -> {:error, "unable to write #{path}: #{inspect(reason)}"}
    end
  end

  @spec rubric_item_ids([rubric_item()]) :: [String.t()]
  defp rubric_item_ids(rubric_items) do
    Enum.map(rubric_items, & &1["rubric_item_id"])
  end

  @spec rubric_threshold_ids(rubric()) :: [String.t()]
  defp rubric_threshold_ids(rubric) do
    rubric["items"]
    |> Enum.map(& &1["threshold_id"])
    |> Enum.uniq()
  end

  @spec weighted_score([rubric_item()], map()) :: float()
  defp weighted_score(rubric_items, rubric_scores) do
    total_weight = Enum.reduce(rubric_items, 0.0, &(&1["weight"] + &2))

    raw_score =
      Enum.reduce(rubric_items, 0.0, fn item, acc ->
        acc + item["weight"] * Map.fetch!(rubric_scores, item["rubric_item_id"])
      end)

    Float.round(raw_score / total_weight, 4)
  end

  @spec average_score([map()]) :: float()
  defp average_score(case_reports) do
    total = Enum.reduce(case_reports, 0.0, fn case_report, acc -> acc + case_report["score"] end)
    Float.round(total / max(length(case_reports), 1), 4)
  end

  @spec case_values(dataset(), String.t()) :: [String.t()]
  defp case_values(dataset, key) do
    dataset["cases"]
    |> Enum.map(& &1[key])
    |> Enum.uniq()
  end

  @spec unique_summary_value([String.t()]) :: String.t()
  defp unique_summary_value([single]), do: single
  defp unique_summary_value(values) when is_list(values), do: Enum.sort(values) |> Enum.join(",")

  @spec sanitize_case_filename(String.t()) :: String.t()
  defp sanitize_case_filename(dataset_case_id) do
    Regex.replace(~r/[^A-Za-z0-9._-]+/, dataset_case_id, "_")
  end

  @spec digest(term()) :: String.t()
  defp digest(term) do
    term
    |> Jason.encode_to_iodata!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec unique_id(String.t()) :: String.t()
  defp unique_id(prefix) do
    "#{prefix}-#{System.system_time(:microsecond)}-#{System.unique_integer([:positive, :monotonic])}"
  end

  @spec now_iso8601() :: String.t()
  defp now_iso8601 do
    DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  end

  @spec valid_score?(term()) :: boolean()
  defp valid_score?(value) when is_integer(value), do: value >= 0 and value <= 1
  defp valid_score?(value) when is_float(value), do: value >= 0.0 and value <= 1.0
  defp valid_score?(_value), do: false

  @spec reduce_until_error([term()], (term() -> :ok | {:error, String.t()})) :: :ok | {:error, String.t()}
  defp reduce_until_error(items, validator) do
    Enum.reduce_while(items, :ok, fn item, :ok ->
      case validator.(item) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @spec first_error([:ok | {:error, String.t()}]) :: :ok | {:error, String.t()}
  defp first_error(results) do
    Enum.find(results, :ok, &match?({:error, _}, &1))
  end

  @spec validate_reference_scores(dataset_case(), MapSet.t(String.t())) :: :ok | {:error, String.t()}
  defp validate_reference_scores(dataset_case, valid_item_ids) do
    case Map.get(dataset_case, "reference_scores") do
      nil ->
        :ok

      reference_scores when is_map(reference_scores) ->
        reference_scores
        |> normalize_keys()
        |> valid_reference_scores?(valid_item_ids, dataset_case)

      _ ->
        invalid_reference_scores_error(dataset_case)
    end
  end

  @spec valid_reference_scores?(map(), MapSet.t(String.t()), dataset_case()) :: :ok | {:error, String.t()}
  defp valid_reference_scores?(reference_scores, valid_item_ids, dataset_case) do
    if Enum.all?(reference_scores, fn {rubric_item_id, value} ->
         MapSet.member?(valid_item_ids, rubric_item_id) and valid_score?(value)
       end) do
      :ok
    else
      invalid_reference_scores_error(dataset_case)
    end
  end

  @spec invalid_reference_scores_error(dataset_case()) :: {:error, String.t()}
  defp invalid_reference_scores_error(dataset_case) do
    {:error, "invalid reference_scores for dataset_case_id #{Map.get(dataset_case, "dataset_case_id", "unknown")}"}
  end

  @spec write_case_reports(Path.t(), [map()]) :: :ok | {:error, String.t()}
  defp write_case_reports(cases_dir, case_reports) do
    reduce_until_error(case_reports, fn case_report ->
      case_filename = sanitize_case_filename(case_report["dataset_case_id"]) <> ".json"
      case_path = Path.join(cases_dir, case_filename)
      write_json(case_path, case_report)
    end)
  end

  @spec present_string?(term()) :: boolean()
  defp present_string?(value) when is_binary(value), do: String.trim(value) != ""
  defp present_string?(_value), do: false

  @spec normalize_keys(term()) :: term()
  defp normalize_keys(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), normalize_keys(nested_value)} end)
    |> Enum.into(%{})
  end

  defp normalize_keys(value) when is_list(value), do: Enum.map(value, &normalize_keys/1)
  defp normalize_keys(value), do: value
end
