<p align="center"><img src="Resources/Icon/icon_1024.png" width="128" alt="Yaikus Studio icon"></p>

<h1 align="center">Yaikus Studio</h1>

<p align="center"><b>Turn today's news into short videos — with your own AI.</b><br>
A free, open-source Mac app for creators who are just starting out, and for anyone who wants their AI agent to do the heavy lifting.</p>

<p align="center"><a href="../../releases/latest"><b>⬇ Download for Mac</b></a> · <a href="README.es.md">Español</a></p>

---

## Who it's for

**New creators.** You know what you want to post, but making a video every day is slow. Yaikus Studio gives you a simple loop: pick a story, review a script that follows *your* rules, preview, and export an MP4 ready for TikTok, Reels, Shorts or YouTube. No editing software, no timeline, no subscription.

**People who build with agents.** Already running Claude, OpenClaw, Hermes, a Grok bot or your own agent? Yaikus Studio ships with a local **MCP server**, so your agent can read the news, read your rules, write the script, pick footage and render the video — while you stay in control of what gets published.

## What it does

1. **Collect** — add RSS feeds or article links; stories show up in one list.
2. **Choose** — click the story you want to turn into a video.
3. **Write** — your AI drafts the script (or your agent submits one). The app **validates it** against your rules: word count, hook length, banned phrases, no links or hashtags — and asks for a fix when it doesn't pass.
4. **Preview & tweak** — edit the title, hook and script, swap the background, change the format.
5. **Export** — a finished MP4 with voice, animated captions and your background. You decide where to publish it.

### Highlights

- **Your rules, your tone.** A playbook you can edit: style instructions, word limits, banned phrases, language, spoken outro.
- **Right format for each platform.** Vertical 9:16 for TikTok, Instagram Reels and YouTube Shorts (with each app's safe areas), or horizontal 16:9 for YouTube.
- **Bring your own AI.** Claude, any OpenAI-compatible API (OpenAI, Grok, Ollama, OpenRouter, LM Studio…), or an external agent over MCP.
- **Bring your own voice.** The built-in Mac voice (free, works offline), an OpenAI-compatible text-to-speech endpoint, or ElevenLabs.
- **Backgrounds that are yours to use.** The story's image, your own image or video, or royalty-free stock footage from Pexels (with your free API key).
- **Native and light.** A real macOS app: no Python, no ffmpeg, no extra installs. English and Spanish interface.
- **Private by design.** No accounts, no telemetry. API keys live in the macOS Keychain.

## Connect your agent (MCP)

Open **Connect agents** in the app, copy the command, and your agent gets these tools:

`list_news` · `get_rules` · `create_project` · `submit_script` (validated) · `get_project` · `find_stock_footage` · `set_background_url` · `set_platform` · `render_video`

With Claude Code, for example:

```bash
claude mcp add --transport http yaikus-studio http://127.0.0.1:8741/mcp \
  --header "Authorization: Bearer <your token>"
```

Then ask: *"Pick the most interesting story from Yaikus Studio, write a 45-second script following my rules, and render it for Reels."*

The server only listens on `127.0.0.1` and requires the token shown in the app.

## Install

1. Download the latest `.dmg` from **[Releases](../../releases/latest)**, open it and drag **Yaikus Studio** to **Applications**. Requires macOS 14 or later.
2. The app is signed with a Developer ID and **notarized by Apple**, so it opens like any other app, with no security warnings.
3. In the app: add a source in **Sources**, connect your AI in **Agent** (or use **Connect agents**), pick a voice in **Voice**, and create your first video from **News**.

Each release includes a `SHA256SUMS.txt` so you can verify the download: `shasum -a 256 YaikusStudio-*.dmg`.

## Status

This is **v0.1 — an early release**. It works end to end, but expect rough edges. Known limits: the Intel (x86_64) build is compiled but hasn't been tested on real hardware; the stock-footage and ElevenLabs integrations are written against their public APIs but haven't been run against live accounts. Issues and feedback are very welcome.

## Privacy

The app only talks to the sources you add, the AI and voice services you connect, Pexels if you add a key, and GitHub to check for new versions (you can turn that off). Nothing about you or your videos is sent to us.

## Contributing

Pull requests are welcome. Run the tests with `swift test` and build the app with `./packaging/build_app.sh`.

## License

Code: [MIT](LICENSE). The **Yaikus Studio** name and icon are not covered by the license — see [TRADEMARKS.md](TRADEMARKS.md).
