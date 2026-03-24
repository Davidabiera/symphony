defmodule Mix.Tasks.Symphony.Eval.Run do
  use Mix.Task

  alias SymphonyElixir.Eval

  @moduledoc """
  Runs the Phase 0 eval pipeline and writes manifest plus case artifacts.
  """
  @shortdoc "Runs the Phase 0 eval pipeline"

  @switches [
    dataset: :string,
    rubric: :string,
    output_dir: :string,
    eval_id: :string,
    rel_gate_id: :string,
    smoke: :boolean,
    help: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, argv, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      Keyword.get(opts, :help, false) ->
        Mix.shell().info(usage())

      invalid != [] ->
        Mix.raise("Invalid option: #{format_invalid_option(invalid)}")

      argv != [] ->
        Mix.raise(usage())

      true ->
        with {:ok, dataset_path} <- require_option(Keyword.get(opts, :dataset), "--dataset"),
             {:ok, rubric_path} <- require_option(Keyword.get(opts, :rubric), "--rubric"),
             {:ok, output_dir} <- require_option(Keyword.get(opts, :output_dir), "--output-dir"),
             {:ok, eval_id} <- require_option(Keyword.get(opts, :eval_id), "--eval-id"),
             {:ok, rel_gate_id} <- require_option(Keyword.get(opts, :rel_gate_id), "--rel-gate-id"),
             {:ok, result} <-
               Eval.run(dataset_path, rubric_path, output_dir, eval_id, rel_gate_id, smoke: Keyword.get(opts, :smoke, false)) do
          Mix.shell().info(Jason.encode!(result, pretty: true))
        else
          {:error, reason} -> Mix.raise(reason)
        end
    end
  end

  @spec require_option(String.t() | nil, String.t()) :: {:ok, String.t()} | {:error, String.t()}
  defp require_option(value, option_name) when is_binary(value) do
    trimmed = String.trim(value)

    if trimmed == "" do
      {:error, "Missing required option #{option_name}"}
    else
      {:ok, trimmed}
    end
  end

  defp require_option(_value, option_name), do: {:error, "Missing required option #{option_name}"}

  @spec format_invalid_option([{String.t(), term()}]) :: String.t()
  defp format_invalid_option([{option_name, _value} | _rest]), do: option_name

  @spec usage() :: String.t()
  defp usage do
    "Usage: mix symphony.eval.run --dataset /path/to/dataset.json --rubric /path/to/rubric.json --output-dir /path/to/output --eval-id EVAL-001 --rel-gate-id RG-P0-001 [--smoke]"
  end
end
