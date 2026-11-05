#!/usr/bin/env python3
"""Find anime films and open their streaming links in a browser."""

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

API_URL = "https://api.jikan.moe/v4"


def fetch_data(path, params=None):
    url = API_URL + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, headers={"User-Agent": "anime-film-cli/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 429:
            raise RuntimeError("The movie service is rate-limiting requests. Try again shortly.") from error
        raise RuntimeError(f"The movie service returned HTTP {error.code}.") from error
    except (urllib.error.URLError, TimeoutError, OSError) as error:
        raise RuntimeError("Could not reach the movie service. Check your connection and try again.") from error
    except (ValueError, UnicodeError) as error:
        raise RuntimeError("The movie service returned an invalid response.") from error
    if not isinstance(payload, dict) or not isinstance(payload.get("data"), list):
        raise RuntimeError("The movie service returned an invalid response.")
    return payload["data"]


def choose(prompt, count):
    while True:
        answer = input(prompt).strip()
        if answer.lower() in ("q", "quit"):
            return None
        if answer.isdecimal():
            number = int(answer)
            if 1 <= number <= count:
                return number - 1
        print(f"Enter a number from 1 to {count}, or q to quit.")


def search_movies(query):
    results = fetch_data("/anime", {"q": query, "type": "movie", "limit": 10})
    return [item for item in results if isinstance(item, dict)
            and isinstance(item.get("mal_id"), int) and item["mal_id"] > 0
            and isinstance(item.get("title"), str) and item["title"].strip()]


def streaming_links(movie_id):
    results = fetch_data(f"/anime/{movie_id}/streaming")
    links = []
    for item in results:
        if not isinstance(item, dict) or not isinstance(item.get("name"), str) or not isinstance(item.get("url"), str):
            continue
        try:
            url = urllib.parse.urlsplit(item["url"])
            if url.scheme.lower() not in ("http", "https") or not url.hostname:
                continue
        except ValueError:
            continue
        links.append(item)
    return links


def main(argv=None):
    parser = argparse.ArgumentParser(description="Find anime films and open streaming-provider links.")
    parser.add_argument("query", nargs="*", help="film title to search for (prompted if omitted)")
    args = parser.parse_args(argv)

    try:
        query = " ".join(args.query).strip() if args.query else input("Search for an anime film: ").strip()
        if not query:
            print("Please provide a film title.", file=sys.stderr)
            return 1

        movies = search_movies(query)
        if not movies:
            print("No films found. Try another title.")
            return 0
        print("\nFilms:")
        for index, movie in enumerate(movies, 1):
            print(f"  {index}. {movie['title']}")
        selected = choose("Choose a film (or q to quit): ", len(movies))
        if selected is None:
            return 0

        movie = movies[selected]
        links = streaming_links(movie["mal_id"])
        if not links:
            print(f"No streaming links were found for {movie['title']}.")
            return 0
        print(f"\nStreaming links for {movie['title']}:")
        for index, link in enumerate(links, 1):
            print(f"  {index}. {link['name']}: {link['url']}")
        selected = choose("Open a link in your browser (or q to quit): ", len(links))
        if selected is not None and not webbrowser.open(links[selected]["url"]):
            print("Could not open a browser. Use the link above instead.")
        return 0
    except (EOFError, KeyboardInterrupt):
        print("\nGoodbye.")
        return 0
    except RuntimeError as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
