import contextlib
import io
import json
import unittest
import urllib.error
from unittest import mock

import anime


class AnimeCliTests(unittest.TestCase):
    def test_fetch_data_encodes_search_and_returns_data(self):
        response = mock.MagicMock()
        response.__enter__.return_value = io.BytesIO(json.dumps({"data": [{"title": "Film"}]}).encode())
        with mock.patch("anime.urllib.request.urlopen", return_value=response) as open_url:
            self.assertEqual(anime.fetch_data("/anime", {"q": "a & b", "type": "movie"}), [{"title": "Film"}])
        request = open_url.call_args.args[0]
        self.assertEqual(request.full_url, "https://api.jikan.moe/v4/anime?q=a+%26+b&type=movie")
        self.assertEqual(open_url.call_args.kwargs["timeout"], 15)

    def test_errors_are_reported(self):
        errors = [urllib.error.URLError("offline"), TimeoutError(),
                  urllib.error.HTTPError("url", 429, "limited", {}, None)]
        for error in errors:
            with self.subTest(error=error), mock.patch("anime.urllib.request.urlopen", side_effect=error):
                with self.assertRaises(RuntimeError):
                    anime.fetch_data("/anime")
        response = mock.MagicMock()
        response.__enter__.return_value = io.BytesIO(b"not json")
        with mock.patch("anime.urllib.request.urlopen", return_value=response):
            with self.assertRaisesRegex(RuntimeError, "invalid response"):
                anime.fetch_data("/anime")

    def test_streaming_links_only_accept_web_urls(self):
        data = [{"name": "Provider", "url": "https://example.com/film"},
                {"name": "Bad", "url": "javascript:alert(1)"},
                {"name": "Bad", "url": "https://"}, None]
        with mock.patch("anime.fetch_data", return_value=data):
            self.assertEqual(anime.streaming_links(1), [data[0]])

    def test_search_select_and_open(self):
        movies = [{"mal_id": 1, "title": "Example Film"}]
        links = [{"name": "Provider", "url": "https://example.com/film"}]
        with mock.patch("anime.fetch_data", side_effect=[movies, links]) as fetch, \
             mock.patch("builtins.input", side_effect=["wrong", "1", "1"]), \
             mock.patch("anime.webbrowser.open", return_value=True) as browser, \
             contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(anime.main(["Example", "Film"]), 0)
        self.assertIn("Enter a number", output.getvalue())
        self.assertIn("Provider: https://example.com/film", output.getvalue())
        fetch.assert_any_call("/anime", {"q": "Example Film", "type": "movie", "limit": 10})
        fetch.assert_any_call("/anime/1/streaming")
        browser.assert_called_once_with("https://example.com/film")

    def test_no_results_no_links_and_quit(self):
        movie = {"mal_id": 1, "title": "Example"}
        with mock.patch("anime.fetch_data", return_value=[]), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(anime.main(["missing"]), 0)
            self.assertIn("No films found", output.getvalue())
        with mock.patch("anime.fetch_data", side_effect=[[movie], []]), \
             mock.patch("builtins.input", return_value="1"), contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(anime.main(["Example"]), 0)
            self.assertIn("No streaming links", output.getvalue())
        with mock.patch("anime.fetch_data", return_value=[movie]) as fetch, \
             mock.patch("builtins.input", return_value="q"), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(anime.main(["Example"]), 0)
            self.assertEqual(fetch.call_count, 1)

    def test_empty_input_and_service_error(self):
        with mock.patch("builtins.input", return_value="  "), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(anime.main([]), 1)
        with mock.patch("anime.search_movies", side_effect=RuntimeError("offline")), \
             contextlib.redirect_stderr(io.StringIO()) as output:
            self.assertEqual(anime.main(["Example"]), 1)
            self.assertIn("offline", output.getvalue())


if __name__ == "__main__":
    unittest.main()
