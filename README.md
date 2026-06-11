# DailyDerjaTools

Tooling for the [Daily Derja](https://dailyderja.com) project. Currently this
provides a Mix task that generates [ElevenLabs](https://elevenlabs.io) text-to-speech
audio files for vocabulary and example sentences from a CSV.

## Generating TTS audio

```sh
mix derja.tts examples/daif-examples.csv
mix derja.tts examples/daif-examples.csv --out /absolute/path/to/static/audio
```

The task reads each row of the CSV and, unless a matching `<slug>.mp3` already
exists in the output directory, calls the ElevenLabs API and writes the audio.
Existing files are skipped, so the task is safe to re-run.

By default audio is written to `static/audio`. Use `--out` (alias `-o`) to
override the output directory.

### Environment variables

The task reads its credentials from the environment. If a `.env` file is present
in the project root it is loaded automatically (via `dotenvy`).

| Variable | Description |
| --- | --- |
| `ELEVENLABS_API_KEY` | Your ElevenLabs API key |
| `ELEVENLABS_MALE_VOICE_ID` | Shami (Levantine) male voice id |
| `ELEVENLABS_FEMALE_VOICE_ID` | Shami (Levantine) female voice id |
| `ELEVENLABS_TUNISIAN_MALE_VOICE_ID` | Tunisian male voice id |
| `ELEVENLABS_TUNISIAN_FEMALE_VOICE_ID` | Tunisian female voice id |

### CSV format

```csv
slug,voice,text,en,post,dialect
hadid,male,حَديد,"iron; metal",iron,both
strike-iron-hot,male,"إضرب الحديد وهو حامي.","Strike the iron while it's hot.",iron,shami
narqod,male,نَرْقُد,"I sleep; I go to sleep",tunisian-daily-2,tunisian
```

| Column | Description |
| --- | --- |
| `slug` | Output file name (without extension); audio is written to `<slug>.mp3` |
| `voice` | `male` or `female` |
| `text` | The Arabic text to synthesize |
| `en` | English gloss/translation (metadata only; not sent to TTS) |
| `post` | The post the example belongs to (metadata only) |
| `dialect` | `shami`, `tunisian`, or `both`; selects which voice is used |

The combination of `voice` and `dialect` determines the ElevenLabs voice id:

* `dialect` `shami` or `both` → the Shami voice (`ELEVENLABS_*_VOICE_ID`)
* `dialect` `tunisian` → the Tunisian voice (`ELEVENLABS_TUNISIAN_*_VOICE_ID`)

Fields containing commas must be quoted with double quotes.

## Tests

```sh
mix test
```

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `daily_derja_tools` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:daily_derja_tools, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/daily_derja_tools>.
