defmodule Mix.Tasks.Derja.TtsTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Derja.Tts

  @voices %{
    "shami" => %{"male" => "shami-male-id", "female" => "shami-female-id"},
    "tunisian" => %{"male" => "tunisian-male-id", "female" => "tunisian-female-id"}
  }

  describe "parse_rows/1" do
    test "parses headers and rows into string-keyed maps" do
      csv = """
      slug,voice,text,en,post,dialect
      hadid,male,حَديد,"iron; metal",iron,both
      """

      assert Tts.parse_rows(csv) == [
               %{
                 "slug" => "hadid",
                 "voice" => "male",
                 "text" => "حَديد",
                 "en" => "iron; metal",
                 "post" => "iron",
                 "dialect" => "both"
               }
             ]
    end

    test "honors quoting so commas inside text are preserved" do
      csv = """
      slug,voice,text,en,post,dialect
      strike-iron-hot,male,"إضرب الحديد وهو حامي.","Strike the iron while it's hot.",iron,shami
      """

      assert [row] = Tts.parse_rows(csv)
      assert row["text"] == "إضرب الحديد وهو حامي."
      assert row["en"] == "Strike the iron while it's hot."
      assert row["dialect"] == "shami"
    end

    test "trims whitespace from headers and values" do
      csv = "slug , voice , text , en , post , dialect\n narqod , male , نَرْقُد , I sleep , p , tunisian \n"

      assert [row] = Tts.parse_rows(csv)
      assert row["slug"] == "narqod"
      assert row["voice"] == "male"
      assert row["dialect"] == "tunisian"
    end

    test "returns an empty list for header-only or empty input" do
      assert Tts.parse_rows("slug,voice,text,en,post,dialect\n") == []
      assert Tts.parse_rows("") == []
    end

    test "parses multiple rows" do
      csv = """
      slug,voice,text,en,post,dialect
      hadid,male,حَديد,iron,iron,both
      barsha,female,برشة,a lot,diffs,tunisian
      """

      assert [first, second] = Tts.parse_rows(csv)
      assert first["slug"] == "hadid"
      assert second["slug"] == "barsha"
    end
  end

  describe "voice_id_for/3" do
    test "shami dialect uses the shami voices" do
      assert Tts.voice_id_for(@voices, "shami", "male") == "shami-male-id"
      assert Tts.voice_id_for(@voices, "shami", "female") == "shami-female-id"
    end

    test "tunisian dialect uses the tunisian voices" do
      assert Tts.voice_id_for(@voices, "tunisian", "male") == "tunisian-male-id"
      assert Tts.voice_id_for(@voices, "tunisian", "female") == "tunisian-female-id"
    end

    test "both dialect falls back to the shami voices" do
      assert Tts.voice_id_for(@voices, "both", "male") == "shami-male-id"
      assert Tts.voice_id_for(@voices, "both", "female") == "shami-female-id"
    end

    test "is case-insensitive and trims whitespace" do
      assert Tts.voice_id_for(@voices, " Tunisian ", " MALE ") == "tunisian-male-id"
      assert Tts.voice_id_for(@voices, "SHAMI", "Female") == "shami-female-id"
    end

    test "unknown dialect falls back to shami voices" do
      assert Tts.voice_id_for(@voices, "msa", "male") == "shami-male-id"
    end

    test "returns nil for an unknown voice" do
      assert Tts.voice_id_for(@voices, "shami", "robot") == nil
    end
  end
end
