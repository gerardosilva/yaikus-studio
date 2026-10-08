import Foundation
import Observation

/// Interface strings in English and Spanish, switchable instantly from inside the app.
@Observable
final class Strings {
    static let shared = Strings()
    var code = "en"

    func t(_ key: String, _ args: [String: Any] = [:]) -> String {
        var s = Self.table[code]?[key] ?? Self.table["en"]![key] ?? key
        for (k, v) in args { s = s.replacingOccurrences(of: "{\(k)}", with: "\(v)") }
        return s
    }

    static let table: [String: [String: String]] = [
        "en": [
            "nav.news": "News", "nav.videos": "Videos", "nav.sources": "Sources", "nav.rules": "Rules", "nav.agent": "Agent", "nav.voice": "Voice", "nav.connect": "Connect agents",
            "language": "Language", "lang.system": "System", "update.available": "Version {v} is available (you have {cur}).", "update.get": "Download",
            "common.save": "Save", "common.saved": "Saved", "common.cancel": "Cancel", "common.remove": "Remove", "common.optional": "optional", "common.copy": "Copy", "common.copied": "Copied",
            "status.generating": "Writing script…", "status.rendering": "Rendering…", "status.fetching": "Finding footage…", "status.draft": "Draft", "status.ready": "Ready", "status.error": "Error",

            "news.title": "News", "news.refresh": "Refresh", "news.loading": "Reading sources…", "news.empty": "No news yet. Add sources in the Sources tab.",
            "news.create": "Create video", "news.sourceError": "Could not read {name}",

            "videos.empty": "Pick a story in News to create a video, or select one from the list.", "videos.none": "No videos yet",
            "editor.openNote": "Open story", "editor.format": "Format", "editor.title": "Title (shown on top of the video)", "editor.hook": "Hook (first spoken sentence)",
            "editor.script": "Script", "editor.words": "{n} words", "editor.background": "Background", "editor.askChanges": "Ask your agent for changes",
            "editor.askPlaceholder": "Optional notes: “shorter”, “mention the price”…", "editor.regenerate": "Regenerate",
            "editor.render": "Render video", "editor.rerender": "Render again", "editor.upload": "Upload image or video", "editor.stock": "Find stock footage", "editor.noBg": "Remove",
            "editor.noVideo": "No video yet. Review the script and press Render.", "editor.export": "Save video…", "editor.reveal": "Show in Finder", "editor.delete": "Delete project",
            "bg.none": "solid color", "bg.article": "story image", "bg.image": "your image", "bg.video": "your video", "bg.stock": "stock footage", "bg.credit": "Video by {author} on Pexels",

            "plat.tiktok": "TikTok", "plat.reels": "Instagram Reels", "plat.shorts": "YouTube Shorts", "plat.youtube": "YouTube (horizontal)",
            "orient.vertical": "vertical 9:16", "orient.horizontal": "horizontal 16:9",

            "prob.empty": "The script is empty.", "prob.too_short": "The script has {n} words; the minimum is {min}.", "prob.too_long": "The script has {n} words; the maximum is {max}.",
            "prob.hook_long": "The hook has {n} words; the maximum is {max}.", "prob.banned": "It contains the banned phrase “{phrase}”.", "prob.junk": "The script has links, hashtags or [1] citations; remove them.",

            "sources.title": "Sources", "sources.rss": "RSS feed", "sources.link": "Article link", "sources.name": "Name (optional)", "sources.add": "Add", "sources.empty": "No sources yet.",

            "rules.title": "Rules", "rules.intro": "Your agent receives these rules for every story, and the app checks its answer against the limits.",
            "rules.platform": "Target platform", "rules.platformHint": "Prepares the video format: vertical (TikTok, Reels, Shorts) or horizontal (YouTube). Picking one fills in suggested word limits. You decide where to publish.",
            "rules.instructions": "Instructions for your agent (style, tone, what to avoid)", "rules.min": "Script minimum words", "rules.max": "Script maximum words", "rules.hookMax": "Hook maximum words",
            "rules.language": "Content language", "rules.banned": "Banned phrases (one per line)", "rules.voice": "Voice", "rules.voiceAuto": "Automatic", "rules.voiceId": "Voice name or ID at your voice provider",
            "rules.outro": "Spoken outro (call to action)", "rules.reset": "Restore defaults",

            "agent.title": "Agent", "agent.intro": "Connect the AI that writes the scripts inside the app. To drive the app from an external agent (OpenClaw, Hermes, Claude Code…), use Connect agents. Keys are stored in the macOS Keychain.",
            "agent.provider": "Provider", "agent.mock": "Demo (no AI)", "agent.anthropic": "Claude (Anthropic)", "agent.openai": "OpenAI-compatible",
            "agent.mockHint": "Builds the script from a template, just to try the flow.", "agent.anthropicHint": "Paste your Anthropic API key.", "agent.openaiHint": "OpenAI, Grok (xAI), Ollama, OpenRouter, LM Studio… Set the base URL.",
            "agent.model": "Model", "agent.modelHint": "empty = default model", "agent.key": "API key", "agent.base": "Base URL",
            "stock.title": "Stock footage (Pexels) · optional", "stock.hint": "Free API key from pexels.com/api. Lets you search royalty-free video for backgrounds.",

            "voice.title": "Voice", "voice.intro": "Connect the voice service for your videos. Nothing is bundled: you choose and own the account.", "voice.provider": "Provider",
            "voice.system": "Mac voice (built in)", "voice.openai": "OpenAI-compatible (/audio/speech)", "voice.elevenlabs": "ElevenLabs",
            "voice.systemHint": "Free, offline, no setup. Pick the exact voice in Rules. More voices: System Settings → Accessibility → Spoken Content.",
            "voice.openaiHint": "OpenAI or any server with the same endpoint. In Rules, the voice is its name (e.g. alloy).",
            "voice.elevenlabsHint": "Paste your API key. In Rules, put the Voice ID. Gives exact word timing for captions.",
            "voice.test": "Play a sample", "voice.testing": "Generating sample…",

            "connect.title": "Connect agents", "connect.intro": "Let any MCP-capable agent (Claude, OpenClaw, Hermes, Grok bot…) drive Yaikus Studio: read the news and your rules, write the script, pick footage and render the video. It only listens on this Mac.",
            "connect.enabled": "Enable MCP server", "connect.port": "Port", "connect.status": "Status", "connect.running": "Running on 127.0.0.1:{port}", "connect.stopped": "Stopped", "connect.failed": "Could not start: {msg}",
            "connect.url": "Server URL", "connect.token": "Access token", "connect.show": "Show", "connect.hide": "Hide", "connect.regen": "Regenerate", "connect.regenWarn": "Agents using the old token will stop working.",
            "connect.claudeCode": "Claude Code", "connect.generic": "Other clients (JSON)", "connect.genericHint": "For clients that only support stdio, use mcp-remote: it bridges to this URL.",
            "connect.tools": "What agents can do", "connect.toolsText": "list_news · get_rules · create_project · submit_script (validated) · get_project · find_stock_footage · set_background_url · set_platform · render_video",

            "err.invalid_url": "Paste a URL that starts with http.", "err.not_found": "Not found.", "err.agent_key_missing": "Add your AI API key in the Agent tab.", "err.agent_key_invalid": "The AI service rejected the API key.",
            "err.voice_key_missing": "Add the API key of your voice service in the Voice tab.", "err.voice_key_invalid": "The voice service rejected the API key.", "err.voice_id_missing": "Set the Voice ID in Rules.",
            "err.stock_key_missing": "Add your Pexels API key in the Agent tab first.", "err.stock_key_invalid": "Pexels rejected the API key.", "err.stock_no_results": "No stock footage found. Try other words in the title or hook.",
        ],
        "es": [
            "nav.news": "Noticias", "nav.videos": "Videos", "nav.sources": "Fuentes", "nav.rules": "Reglas", "nav.agent": "Agente", "nav.voice": "Voz", "nav.connect": "Conectar agentes",
            "language": "Idioma", "lang.system": "Sistema", "update.available": "Ya está disponible la versión {v} (tienes la {cur}).", "update.get": "Descargar",
            "common.save": "Guardar", "common.saved": "Guardado", "common.cancel": "Cancelar", "common.remove": "Quitar", "common.optional": "opcional", "common.copy": "Copiar", "common.copied": "Copiado",
            "status.generating": "Escribiendo guion…", "status.rendering": "Renderizando…", "status.fetching": "Buscando footage…", "status.draft": "Borrador", "status.ready": "Listo", "status.error": "Error",

            "news.title": "Noticias", "news.refresh": "Actualizar", "news.loading": "Leyendo fuentes…", "news.empty": "Aún no hay noticias. Agrega fuentes en la pestaña Fuentes.",
            "news.create": "Crear video", "news.sourceError": "No se pudo leer {name}",

            "videos.empty": "Elige una noticia en Noticias para crear un video, o selecciona uno de la lista.", "videos.none": "Aún no hay videos",
            "editor.openNote": "Abrir nota", "editor.format": "Formato", "editor.title": "Título (arriba del video)", "editor.hook": "Hook (primera frase hablada)",
            "editor.script": "Guion", "editor.words": "{n} palabras", "editor.background": "Fondo", "editor.askChanges": "Pedirle cambios al agente",
            "editor.askPlaceholder": "Indicaciones opcionales: “más corto”, “menciona el precio”…", "editor.regenerate": "Regenerar",
            "editor.render": "Renderizar video", "editor.rerender": "Volver a renderizar", "editor.upload": "Subir imagen o video", "editor.stock": "Buscar footage de stock", "editor.noBg": "Quitar",
            "editor.noVideo": "Aún no hay video. Revisa el guion y pulsa Renderizar.", "editor.export": "Guardar video…", "editor.reveal": "Mostrar en Finder", "editor.delete": "Eliminar proyecto",
            "bg.none": "color liso", "bg.article": "imagen de la nota", "bg.image": "tu imagen", "bg.video": "tu video", "bg.stock": "footage de stock", "bg.credit": "Video de {author} en Pexels",

            "plat.tiktok": "TikTok", "plat.reels": "Instagram Reels", "plat.shorts": "YouTube Shorts", "plat.youtube": "YouTube (horizontal)",
            "orient.vertical": "vertical 9:16", "orient.horizontal": "horizontal 16:9",

            "prob.empty": "El guion está vacío.", "prob.too_short": "El guion tiene {n} palabras; el mínimo es {min}.", "prob.too_long": "El guion tiene {n} palabras; el máximo es {max}.",
            "prob.hook_long": "El hook tiene {n} palabras; el máximo es {max}.", "prob.banned": "Contiene la frase prohibida “{phrase}”.", "prob.junk": "El guion trae links, hashtags o citas [1]; quítalos.",

            "sources.title": "Fuentes", "sources.rss": "Feed RSS", "sources.link": "Link de artículo", "sources.name": "Nombre (opcional)", "sources.add": "Agregar", "sources.empty": "Aún no hay fuentes.",

            "rules.title": "Reglas", "rules.intro": "Tu agente recibe estas reglas en cada noticia, y la app valida su respuesta contra los límites.",
            "rules.platform": "Plataforma de destino", "rules.platformHint": "Prepara el formato del video: vertical (TikTok, Reels, Shorts) u horizontal (YouTube). Al elegir una se sugieren los límites de palabras. Tú decides dónde publicar.",
            "rules.instructions": "Instrucciones para tu agente (estilo, tono, qué evitar)", "rules.min": "Mínimo de palabras del guion", "rules.max": "Máximo de palabras del guion", "rules.hookMax": "Máximo de palabras del hook",
            "rules.language": "Idioma del contenido", "rules.banned": "Frases prohibidas (una por línea)", "rules.voice": "Voz", "rules.voiceAuto": "Automática", "rules.voiceId": "Nombre o ID de la voz en tu proveedor",
            "rules.outro": "Cierre hablado (llamada a la acción)", "rules.reset": "Restablecer default",

            "agent.title": "Agente", "agent.intro": "Conecta la IA que escribe los guiones dentro de la app. Para manejar la app desde un agente externo (OpenClaw, Hermes, Claude Code…), usa Conectar agentes. Las llaves se guardan en el Keychain de macOS.",
            "agent.provider": "Proveedor", "agent.mock": "Demo (sin IA)", "agent.anthropic": "Claude (Anthropic)", "agent.openai": "Compatible con OpenAI",
            "agent.mockHint": "Arma el guion con una plantilla, solo para probar el flujo.", "agent.anthropicHint": "Pega tu API key de Anthropic.", "agent.openaiHint": "OpenAI, Grok (xAI), Ollama, OpenRouter, LM Studio… Define la URL base.",
            "agent.model": "Modelo", "agent.modelHint": "vacío = modelo por defecto", "agent.key": "API key", "agent.base": "URL base",
            "stock.title": "Footage de stock (Pexels) · opcional", "stock.hint": "API key gratuita de pexels.com/api. Permite buscar video libre de regalías para el fondo.",

            "voice.title": "Voz", "voice.intro": "Conecta el servicio de voz de tus videos. La app no incluye ninguno: tú eliges y eres dueño de la cuenta.", "voice.provider": "Proveedor",
            "voice.system": "Voz del Mac (incluida)", "voice.openai": "Compatible con OpenAI (/audio/speech)", "voice.elevenlabs": "ElevenLabs",
            "voice.systemHint": "Gratis, sin conexión y sin configurar. La voz exacta se elige en Reglas. Más voces: Ajustes del Sistema → Accesibilidad → Contenido hablado.",
            "voice.openaiHint": "OpenAI o cualquier servidor con el mismo endpoint. En Reglas, la voz es su nombre (ej. alloy).",
            "voice.elevenlabsHint": "Pega tu API key. En Reglas pon el Voice ID. Da tiempos exactos por palabra para los subtítulos.",
            "voice.test": "Escuchar muestra", "voice.testing": "Generando muestra…",

            "connect.title": "Conectar agentes", "connect.intro": "Deja que cualquier agente compatible con MCP (Claude, OpenClaw, Hermes, Grok bot…) maneje Yaikus Studio: lee las noticias y tus reglas, escribe el guion, elige footage y renderiza el video. Solo escucha en este Mac.",
            "connect.enabled": "Activar servidor MCP", "connect.port": "Puerto", "connect.status": "Estado", "connect.running": "Activo en 127.0.0.1:{port}", "connect.stopped": "Detenido", "connect.failed": "No se pudo iniciar: {msg}",
            "connect.url": "URL del servidor", "connect.token": "Token de acceso", "connect.show": "Mostrar", "connect.hide": "Ocultar", "connect.regen": "Regenerar", "connect.regenWarn": "Los agentes que usen el token anterior dejarán de funcionar.",
            "connect.claudeCode": "Claude Code", "connect.generic": "Otros clientes (JSON)", "connect.genericHint": "Para clientes que solo soportan stdio, usa mcp-remote: hace de puente hacia esta URL.",
            "connect.tools": "Qué pueden hacer los agentes", "connect.toolsText": "list_news · get_rules · create_project · submit_script (validado) · get_project · find_stock_footage · set_background_url · set_platform · render_video",

            "err.invalid_url": "Pega una URL que empiece con http.", "err.not_found": "No encontrado.", "err.agent_key_missing": "Agrega la API key de tu IA en la pestaña Agente.", "err.agent_key_invalid": "El servicio de IA rechazó la API key.",
            "err.voice_key_missing": "Agrega la API key de tu servicio de voz en la pestaña Voz.", "err.voice_key_invalid": "El servicio de voz rechazó la API key.", "err.voice_id_missing": "Indica el Voice ID en Reglas.",
            "err.stock_key_missing": "Primero agrega tu API key de Pexels en la pestaña Agente.", "err.stock_key_invalid": "Pexels rechazó la API key.", "err.stock_no_results": "No se encontró footage de stock. Prueba otras palabras en el título o el hook.",
        ],
    ]
}

func t(_ key: String, _ args: [String: Any] = [:]) -> String { Strings.shared.t(key, args) }

/// Translates a core error code; if it is not a known one, shows the original text.
func errorText(_ message: String) -> String {
    let k = "err." + message
    let s = t(k)
    return s == k ? message : s
}
