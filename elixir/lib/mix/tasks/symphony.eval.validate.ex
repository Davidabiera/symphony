defmodule Mix.Tasks.Symphony.Eval.Validate do
  use Mix.Task

  alias SymphonyElixir.Eval

  @moduledoc """
  Validates eval dataset and rubric inputs for the Phase 0 pipeline.
  """
  @shortdoc "Validates eval dataset and rubric inputs"

  @switches [dataset: :string, rubric: :string, help: :boolean]

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
        dataset_path = Keyword.get(opts, :dataset)
        rubric_path = Keyword.get(opts, :rubric)

        with {:ok, dataset_path} <- require_option(dataset_path, "--dataset"),
             {:ok, rubric_path} <- require_option(rubric_path, "--rubric"),
             {:ok, result} <- Eval.validate_inputs(dataset_path, rubric_path) do
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
    "Usage: mix symphony.eval.validate --dataset /path/to/dataset.json --rubric /path/to/rubric.json"
  end
end
