# Anime Film CLI

A small command-line tool for finding anime films and opening streaming-provider links in your browser. It uses the public [Jikan API](https://jikan.moe/), an unofficial MyAnimeList API. It does not host or play videos itself.

## Requirements

- Python 3.8 or newer; no additional packages
- An internet connection and a web browser

## Run

```sh
python3 anime.py
```

Enter a film title when prompted, or pass it directly:

```sh
python3 anime.py Spirited Away
```

Choose a film, then choose a streaming link to open it. Enter `q` at either selection to quit. Links and availability come from Jikan; a film may have no links, and a provider may require a subscription or be unavailable in your region.

## Test

```sh
python3 -m unittest discover -s tests -v
```
