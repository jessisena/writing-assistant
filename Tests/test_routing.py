import pytest

from assistant.routing import HAIKU_MODEL, SONNET_MODEL, pick_model


class TestPickModel:
    def test_short_english_routes_to_haiku(self) -> None:
        assert pick_model("Please send me the report by end of day.") == HAIKU_MODEL

    def test_short_english_question_routes_to_haiku(self) -> None:
        assert pick_model("Can you review this before our meeting tomorrow?") == HAIKU_MODEL

    def test_short_spanish_routes_to_sonnet(self) -> None:
        sentence = "Por favor envíame el informe antes de que termine el día."
        assert pick_model(sentence) == SONNET_MODEL

    def test_short_portuguese_routes_to_sonnet(self) -> None:
        assert pick_model("Por favor me envie o relatório antes do final do dia.") == SONNET_MODEL

    def test_long_english_routes_to_sonnet(self) -> None:
        # 70 words — above the 60-word threshold
        assert pick_model(" ".join(["hello"] * 70)) == SONNET_MODEL

    def test_short_ascii_unknown_word_routes_to_haiku(self) -> None:
        # "Hola" is ASCII with no accents and no romance stopword hits, so the heuristic
        # cannot identify it as non-English and routes to Haiku. Claude detects the actual
        # language regardless, so the polishing is correct either way.
        assert pick_model("Hola") == HAIKU_MODEL

    def test_empty_string_routes_to_sonnet(self) -> None:
        assert pick_model("") == SONNET_MODEL

    def test_accented_chars_routes_to_sonnet(self) -> None:
        # Non-ASCII ratio > 2% should push toward Sonnet
        assert pick_model("Désolé, je suis en retard.") == SONNET_MODEL

    @pytest.mark.parametrize("text,expected", [
        ("Hello how are you today", HAIKU_MODEL),
        ("El proyecto está listo para revisión", SONNET_MODEL),
        # 61 words of English is just over the threshold
        (" ".join(["word"] * 61), SONNET_MODEL),
    ])
    def test_parametrized_routing(self, text: str, expected: str) -> None:
        assert pick_model(text) == expected
