defmodule Mix.Tasks.Derja.Tts do
  use Mix.Task

  @shortdoc "Generate ElevenLabs TTS audio files for Daily Derja examples"

  @moduledoc """
  Generate ElevenLabs TTS audio files from a CSV.

  Usage:

      mix derja.tts examples/word_examples.csv
      mix derja.tts examples/word_examples.csv --out /absolute/path/to/static/audio

  Required environment variables:

      ELEVENLABS_API_KEY
      ELEVENLABS_MALE_VOICE_ID
      ELEVENLABS_FEMALE_VOICE_ID

  CSV format:

      slug,voice,text,en
      daai-01,female,"ما في داعي تصبغي شعرك، طالع حلو هيك.","No need to dye your hair; it looks nice like this."
      daai-02,male,"ما في داعي تعتذر، ما صار شي.","No need to apologize; nothing happened."
  """

  NimbleCSV.define(DailyDerjaCSV, separator: ",", escape: "\"")

  @default_output_dir "static/audio"
  @model_id "eleven_multilingual_v2"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    load_dotenv_if_available()

    {opts, positional, invalid} =
      OptionParser.parse(args,
        switches: [out: :string],
        aliases: [o: :out]
      )

    if invalid != [] do
      Mix.raise("Invalid arguments: #{inspect(invalid)}")
    end

    csv_path =
      case positional do
        [path] ->
          path

        _ ->
          Mix.raise("""
          Usage:

              mix derja.tts examples/file.csv
              mix derja.tts examples/file.csv --out /path/to/static/audio
          """)
      end

    output_dir = Keyword.get(opts, :out, @default_output_dir)

    Mix.shell().info("CSV path: #{csv_path}")
    Mix.shell().info("Output dir: #{Path.expand(output_dir)}")

    api_key = get_env!("ELEVENLABS_API_KEY")

    voices = %{
      "male" => get_env!("ELEVENLABS_MALE_VOICE_ID"),
      "female" => get_env!("ELEVENLABS_FEMALE_VOICE_ID")
    }

    File.mkdir_p!(output_dir)

    rows =
      csv_path
      |> File.read!()
      |> DailyDerjaCSV.parse_string(skip_headers: false)
      |> rows_to_maps()

    Mix.shell().info("Parsed #{length(rows)} row(s).")

    Enum.each(rows, fn row ->
      generate_row!(row, api_key, voices, output_dir)
    end)

    Mix.shell().info("Done.")
  end

  defp rows_to_maps([]), do: []

  defp rows_to_maps([headers | rows]) do
    headers = Enum.map(headers, &String.trim/1)

    Enum.map(rows, fn row ->
      headers
      |> Enum.zip(row)
      |> Map.new(fn {key, value} ->
        {key, String.trim(value)}
      end)
    end)
  end

  defp generate_row!(
         %{"slug" => slug, "voice" => voice, "text" => text},
         api_key,
         voices,
         output_dir
       ) do
    slug = String.trim(slug)
    voice = voice |> String.trim() |> String.downcase()
    text = String.trim(text)

    voice_id =
      Map.get(voices, voice) ||
        Mix.raise("Unknown voice '#{voice}' for slug '#{slug}'. Use male or female.")

    output_path = Path.join(output_dir, "#{slug}.mp3")

    if File.exists?(output_path) do
      Mix.shell().info("Skipping existing file: #{Path.expand(output_path)}")
    else
      Mix.shell().info("Generating #{Path.expand(output_path)}")

      audio =
        generate_tts!(
          api_key: api_key,
          voice_id: voice_id,
          text: text
        )

      File.write!(output_path, audio)
    end
  end

  defp generate_row!(row, _api_key, _voices, _output_dir) do
    Mix.raise("""
    Bad CSV row.

    Expected columns:

        slug,voice,text,en

    Got:

        #{inspect(row)}
    """)
  end

  defp generate_tts!(api_key: api_key, voice_id: voice_id, text: text) do
    url = "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}"

    body = %{
      text: text,
      model_id: @model_id,
      voice_settings: %{
        stability: 0.45,
        similarity_boost: 0.8
      }
    }

    case Req.post(
           url,
           headers: [
             {"xi-api-key", api_key},
             {"accept", "audio/mpeg"},
             {"content-type", "application/json"}
           ],
           json: body,
           receive_timeout: 60_000
         ) do
      {:ok, %{status: status, body: audio}} when status in 200..299 ->
        audio

      {:ok, %{status: status, body: body}} ->
        Mix.raise("ElevenLabs error #{status}: #{inspect(body)}")

      {:error, error} ->
        Mix.raise("Request failed: #{inspect(error)}")
    end
  end

  defp get_env!(name) do
    System.get_env(name) ||
      Mix.raise("Missing required environment variable: #{name}")
  end

  defp load_dotenv_if_available do
    env_path = Path.expand(".env", File.cwd!())

    if Code.ensure_loaded?(Dotenvy) and File.exists?(env_path) do
      Dotenvy.source!(env_path)
    end
  rescue
    _ ->
      :ok
  end
end
