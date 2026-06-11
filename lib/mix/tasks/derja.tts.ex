defmodule Mix.Tasks.Derja.Tts do
  use Mix.Task

  @shortdoc "Generate ElevenLabs TTS audio files for Daily Derja examples"

  @moduledoc """
  Generate ElevenLabs TTS audio files from a CSV.

  Usage:

      mix derja.tts examples/daif-examples.csv
      mix derja.tts examples/daif-examples.csv --out /absolute/path/to/static/audio

  Required environment variables:

      ELEVENLABS_API_KEY
      ELEVENLABS_MALE_VOICE_ID            # Shami (Levantine) male voice
      ELEVENLABS_FEMALE_VOICE_ID          # Shami (Levantine) female voice
      ELEVENLABS_TUNISIAN_MALE_VOICE_ID   # Tunisian male voice
      ELEVENLABS_TUNISIAN_FEMALE_VOICE_ID # Tunisian female voice

  CSV format:

      slug,voice,text,en,post,dialect
      hadid,male,حَديد,"iron; metal",iron,both
      strike-iron-hot,male,"إضرب الحديد وهو حامي.","Strike the iron while it's hot.",iron,shami
      narqod,male,نَرْقُد,"I sleep; I go to sleep",tunisian-daily-2,tunisian

  Columns:

    * `slug`    - output file name (without extension); audio is written to `<slug>.mp3`
    * `voice`   - `male` or `female`
    * `text`    - the Arabic text to synthesize
    * `en`      - English gloss/translation (metadata only; not sent to TTS)
    * `post`    - the post the example belongs to (metadata only)
    * `dialect` - `shami`, `tunisian`, or `both`; selects the voice to use.
                  `both` uses the Shami voice.
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
      "shami" => %{
        "male" => get_env!("ELEVENLABS_MALE_VOICE_ID"),
        "female" => get_env!("ELEVENLABS_FEMALE_VOICE_ID")
      },
      "tunisian" => %{
        "male" => get_env!("ELEVENLABS_TUNISIAN_MALE_VOICE_ID"),
        "female" => get_env!("ELEVENLABS_TUNISIAN_FEMALE_VOICE_ID")
      }
    }

    File.mkdir_p!(output_dir)

    rows =
      csv_path
      |> File.read!()
      |> parse_rows()

    Mix.shell().info("Parsed #{length(rows)} row(s).")

    Enum.each(rows, fn row ->
      generate_row!(row, api_key, voices, output_dir)
    end)

    Mix.shell().info("Done.")
  end

  @doc """
  Parse a CSV string (with headers) into a list of string-keyed maps,
  trimming whitespace from every header and value.
  """
  def parse_rows(csv_string) when is_binary(csv_string) do
    csv_string
    |> DailyDerjaCSV.parse_string(skip_headers: false)
    |> rows_to_maps()
  end

  @doc """
  Resolve the ElevenLabs voice id for a given `dialect` and `voice`.

  `dialect` is one of `"shami"`, `"tunisian"`, or `"both"` (which maps to the
  Shami voices). `voice` is `"male"` or `"female"`. Returns `nil` when no voice
  id is configured for the combination.
  """
  def voice_id_for(voices, dialect, voice) do
    dialect_key =
      case normalize(dialect) do
        "tunisian" -> "tunisian"
        # "shami", "both", and anything else fall back to the Shami voices.
        _ -> "shami"
      end

    get_in(voices, [dialect_key, normalize(voice)])
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
         %{"slug" => slug, "voice" => voice, "text" => text, "dialect" => dialect},
         api_key,
         voices,
         output_dir
       ) do
    slug = String.trim(slug)
    text = String.trim(text)

    voice_id =
      voice_id_for(voices, dialect, voice) ||
        Mix.raise(
          "No voice id for dialect '#{dialect}' / voice '#{voice}' (slug '#{slug}'). " <>
            "Use voice male or female and dialect shami, tunisian, or both."
        )

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

        slug,voice,text,en,post,dialect

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

  defp normalize(value) when is_binary(value), do: value |> String.trim() |> String.downcase()
  defp normalize(value), do: value

  defp get_env!(name) do
    System.get_env(name) ||
      Mix.raise("Missing required environment variable: #{name}")
  end

  defp load_dotenv_if_available do
    env_path = Path.expand(".env", File.cwd!())

    if Code.ensure_loaded?(Dotenvy) and File.exists?(env_path) do
      # Dotenvy.source!/1 returns a map but does NOT mutate the system
      # environment, so push the parsed values into it ourselves. Existing
      # system env vars still win, since Dotenvy overlays them onto the file.
      env_path
      |> Dotenvy.source!()
      |> System.put_env()
    end
  rescue
    _ ->
      :ok
  end
end
