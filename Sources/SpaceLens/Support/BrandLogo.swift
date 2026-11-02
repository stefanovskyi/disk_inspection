import Foundation

/// A bundled product, language, or tool logo. `assetName` matches a PNG in
/// `Resources/BrandLogos`; regenerate those with `Scripts/generate_brand_logos.sh`.
struct BrandLogo: Hashable, Sendable {
    enum Appearance: Hashable, Sendable {
        /// Full-color artwork that stays legible on light and dark surfaces.
        case original
        /// Single-color artwork tinted to the current text color.
        case monochrome
        /// Full-color artwork with dark areas; dark mode draws it on a light backing.
        case lightBacked
    }

    let assetName: String
    let appearance: Appearance

    private init(_ assetName: String, _ appearance: Appearance = .original) {
        self.assetName = assetName
        self.appearance = appearance
    }

    // AI coding tools.
    static let cursor = Self("cursor", .monochrome)
    static let claudeCode = Self("claude-code")
    static let claude = Self("claude")
    static let codex = Self("codex")
    static let openAI = Self("openai", .monochrome)
    static let antigravity = Self("antigravity")
    static let openCode = Self("opencode", .monochrome)
    static let t3Code = Self("t3-code")
    static let gemini = Self("gemini")
    static let kiro = Self("kiro")
    static let windsurf = Self("windsurf", .monochrome)
    static let copilot = Self("copilot")
    static let vsCode = Self("vscode")
    static let sublimeText = Self("sublime-text")
    static let intelliJ = Self("intellij", .lightBacked)
    static let xcode = Self("xcode")
    static let androidStudio = Self("androidstudio")

    // Model runtimes and publishers.
    static let ollama = Self("ollama", .monochrome)
    static let lmStudio = Self("lm-studio", .monochrome)
    static let llamaCpp = Self("llama-cpp")
    static let huggingFace = Self("hugging-face")
    static let meta = Self("meta")
    static let qwen = Self("qwen")
    static let gemma = Self("gemma")
    static let mistral = Self("mistral")
    static let deepSeek = Self("deepseek")
    static let microsoft = Self("microsoft")
    static let nvidia = Self("nvidia")
    static let moonshot = Self("moonshot", .lightBacked)
    static let zhipu = Self("zhipu")
    static let flux = Self("flux", .monochrome)
    static let stability = Self("stability")
    static let apple = Self("apple", .monochrome)

    // Programming languages.
    static let nodeJS = Self("nodejs")
    static let python = Self("python")
    static let java = Self("java", .lightBacked)
    static let typeScript = Self("typescript")
    static let javaScript = Self("javascript")
    static let rust = Self("rust", .monochrome)
    static let go = Self("go")
    static let swift = Self("swift")
    static let kotlin = Self("kotlin")
    static let ruby = Self("ruby")
    static let php = Self("php")
    static let c = Self("c")
    static let cPlusPlus = Self("cplusplus")
    static let cSharp = Self("csharp")
    static let dart = Self("dart")
    static let scala = Self("scala")
    static let lua = Self("lua", .lightBacked)
    static let perl = Self("perl")
    static let elixir = Self("elixir")
    static let haskell = Self("haskell", .lightBacked)
    static let html = Self("html5")
    static let css = Self("css3")
    static let sass = Self("sass")
    static let bash = Self("bash", .lightBacked)

    // Developer tools.
    static let docker = Self("docker")
    static let git = Self("git")
    static let gradle = Self("gradle", .monochrome)
    static let maven = Self("maven")
    static let npm = Self("npm")
    static let yarn = Self("yarn")
    static let pnpm = Self("pnpm")
    static let bun = Self("bun")
    static let deno = Self("deno", .monochrome)
    static let nvm = Self("nvm", .monochrome)
    static let anaconda = Self("anaconda", .lightBacked)
    static let poetry = Self("poetry")
    static let uv = Self("uv")
    static let homebrew = Self("homebrew")
    static let nextJS = Self("nextjs")
    static let turborepo = Self("turborepo")
    static let flutter = Self("flutter")
    static let react = Self("react")
    static let vue = Self("vuejs")
    static let jupyter = Self("jupyter")
    static let cocoaPods = Self("cocoapods")

    // Cloud services and platforms.
    static let aws = Self("aws", .lightBacked)
    static let googleCloud = Self("google-cloud")
    static let azure = Self("azure", .lightBacked)
    static let google = Self("google")
    static let kubernetes = Self("kubernetes")
    static let helm = Self("helm", .lightBacked)
    static let terraform = Self("terraform")
    static let vault = Self("vault")
    static let ansible = Self("ansible", .lightBacked)
    static let vercel = Self("vercel", .monochrome)
    static let netlify = Self("netlify")
    static let heroku = Self("heroku", .lightBacked)
    static let cloudflare = Self("cloudflare")
    static let supabase = Self("supabase")
    static let firebase = Self("firebase")
    static let stripe = Self("stripe")
    static let sentry = Self("sentry", .lightBacked)
    static let datadog = Self("datadog", .lightBacked)
    static let postman = Self("postman")
    static let gitHub = Self("github", .monochrome)
    static let gitLab = Self("gitlab")
    static let bitbucket = Self("bitbucket")
    static let ngrok = Self("ngrok", .lightBacked)
    static let tailscale = Self("tailscale", .monochrome)
    static let convex = Self("convex")
    static let wakaTime = Self("wakatime", .monochrome)
    static let sonarQube = Self("sonarqube")
    static let kaggle = Self("kaggle")

    // Data science and Python frameworks.
    static let streamlit = Self("streamlit")
    static let keras = Self("keras")
    static let tensorFlow = Self("tensorflow")
    static let pyTorch = Self("pytorch")
    static let numPy = Self("numpy")
    static let pandas = Self("pandas", .lightBacked)
    static let sciPy = Self("scipy")
    static let matplotlib = Self("matplotlib")
    static let scikitLearn = Self("scikit-learn")
    static let django = Self("django", .lightBacked)
    static let flask = Self("flask", .monochrome)
    static let fastAPI = Self("fastapi")
    static let langChain = Self("langchain")

    // Web frameworks and tooling.
    static let tailwind = Self("tailwindcss")
    static let esLint = Self("eslint", .lightBacked)
    static let prettier = Self("prettier")
    static let vite = Self("vite")
    static let webpack = Self("webpack")
    static let esbuild = Self("esbuild")
    static let svelte = Self("svelte")
    static let angular = Self("angular")
    static let nuxt = Self("nuxt")
    static let electron = Self("electron")
    static let playwright = Self("playwright")
    static let cypress = Self("cypress")
    static let selenium = Self("selenium")
    static let puppeteer = Self("puppeteer")
    static let jest = Self("jest", .lightBacked)
    static let storybook = Self("storybook")
    static let biome = Self("biome")
    static let shadcn = Self("shadcn", .monochrome)
    static let prisma = Self("prisma", .lightBacked)
    static let drizzle = Self("drizzle", .monochrome)
    static let graphQL = Self("graphql")

    // Databases.
    static let postgres = Self("postgresql", .lightBacked)
    static let mySQL = Self("mysql", .lightBacked)
    static let redis = Self("redis", .lightBacked)
    static let mongoDB = Self("mongodb")
    static let sqlite = Self("sqlite")
    static let elasticsearch = Self("elasticsearch", .lightBacked)
    static let kafka = Self("kafka", .monochrome)
    static let rabbitMQ = Self("rabbitmq")
    static let clickHouse = Self("clickhouse")
    static let cassandra = Self("cassandra", .lightBacked)
    static let mariaDB = Self("mariadb", .lightBacked)
    static let oracle = Self("oracle", .lightBacked)

    // More languages, formats, and command-line tools.
    static let objectiveC = Self("objective-c", .lightBacked)
    static let r = Self("r")
    static let julia = Self("julia")
    static let zig = Self("zig")
    static let nim = Self("nim")
    static let clojure = Self("clojure")
    static let erlang = Self("erlang", .lightBacked)
    static let ocaml = Self("ocaml")
    static let fSharp = Self("fsharp")
    static let visualBasic = Self("visual-basic", .lightBacked)
    static let powerShell = Self("powershell", .lightBacked)
    static let webAssembly = Self("wasm")
    static let solidity = Self("solidity", .monochrome)
    static let groovy = Self("groovy", .lightBacked)
    static let astro = Self("astro", .lightBacked)
    static let laTeX = Self("latex", .monochrome)
    static let markdown = Self("markdown", .monochrome)
    static let json = Self("json", .lightBacked)
    static let yaml = Self("yaml", .lightBacked)
    static let toml = Self("toml", .lightBacked)
    static let fish = Self("fish")
    static let zsh = Self("zsh", .monochrome)
    static let vim = Self("vim")
    static let neovim = Self("neovim")
    static let emacs = Self("emacs", .lightBacked)
    static let tmux = Self("tmux", .lightBacked)
    static let cmake = Self("cmake", .lightBacked)
    static let ffmpeg = Self("ffmpeg")
    static let openSSL = Self("openssl", .lightBacked)
    static let hugo = Self("hugo")
    static let make = Self("make", .lightBacked)
    static let dotNet = Self("dotnet", .lightBacked)
    static let nginx = Self("nginx")
    static let apache = Self("apache", .lightBacked)
    static let linux = Self("linux")
    static let ubuntu = Self("ubuntu")
    static let debian = Self("debian", .lightBacked)

    // Applications.
    static let adobe = Self("adobe")
    static let photoshop = Self("photoshop", .lightBacked)
    static let illustrator = Self("illustrator", .lightBacked)
    static let premierePro = Self("premiere-pro", .lightBacked)
    static let afterEffects = Self("after-effects", .lightBacked)
    static let figma = Self("figma")
    static let sketch = Self("sketch")
    static let notion = Self("notion", .lightBacked)
    static let slack = Self("slack")
    static let discord = Self("discord")
    static let telegram = Self("telegram")
    static let whatsApp = Self("whatsapp")
    static let signal = Self("signal", .lightBacked)
    static let zoom = Self("zoom")
    static let spotify = Self("spotify")
    static let chrome = Self("chrome")
    static let firefox = Self("firefox")
    static let safari = Self("safari")
    static let brave = Self("brave")
    static let arc = Self("arc", .monochrome)
    static let vivaldi = Self("vivaldi")
    static let opera = Self("opera")
    static let dropbox = Self("dropbox")
    static let googleDrive = Self("google-drive")
    static let iCloud = Self("icloud")
    static let mega = Self("mega")
    static let box = Self("box")
    static let onePassword = Self("1password")
    static let bitwarden = Self("bitwarden")
    static let obsidian = Self("obsidian")
    static let raycast = Self("raycast")
    static let iTerm2 = Self("iterm2", .monochrome)
    static let warp = Self("warp")
    static let ghostty = Self("ghostty")
    static let alacritty = Self("alacritty")
    static let zed = Self("zed", .lightBacked)
    static let atom = Self("atom", .monochrome)
    static let unity = Self("unity", .monochrome)
    static let unrealEngine = Self("unreal-engine", .monochrome)
    static let blender = Self("blender")
    static let godot = Self("godot")
    static let steam = Self("steam", .monochrome)
    static let epicGames = Self("epic-games", .monochrome)
    static let vlc = Self("vlc")
    static let plex = Self("plex")
    static let jellyfin = Self("jellyfin")
    static let obsStudio = Self("obs-studio", .monochrome)
    static let daVinciResolve = Self("davinci-resolve", .lightBacked)
    static let audacity = Self("audacity", .lightBacked)
    static let gimp = Self("gimp", .lightBacked)
    static let inkscape = Self("inkscape", .lightBacked)
    static let krita = Self("krita")
    static let vmware = Self("vmware", .lightBacked)
    static let virtualBox = Self("virtualbox", .lightBacked)
    static let nordVPN = Self("nordvpn")
    static let wireGuard = Self("wireguard", .lightBacked)
    static let openVPN = Self("openvpn")
    static let gitKraken = Self("gitkraken")
    static let dataGrip = Self("datagrip", .lightBacked)
    static let pyCharm = Self("pycharm", .lightBacked)
    static let webStorm = Self("webstorm", .lightBacked)
    static let cLion = Self("clion", .lightBacked)
    static let goLand = Self("goland", .lightBacked)
    static let phpStorm = Self("phpstorm", .lightBacked)
    static let rider = Self("rider", .lightBacked)
    static let rubyMine = Self("rubymine", .lightBacked)
    static let jetBrains = Self("jetbrains")
    static let loom = Self("loom")
    static let anki = Self("anki")
    static let qBittorrent = Self("qbittorrent", .lightBacked)
    static let wireshark = Self("wireshark", .lightBacked)
    static let libreOffice = Self("libreoffice")
    static let gitea = Self("gitea")
    static let sourcetree = Self("sourcetree", .lightBacked)
    static let mpv = Self("mpv", .lightBacked)
    static let sonarr = Self("sonarr")
    static let lens = Self("lens")
    static let rStudio = Self("rstudio")

    // More AI tools, services, and model publishers.
    static let kiloCode = Self("kilo-code", .monochrome)
    static let rooCode = Self("roo-code", .monochrome)
    static let trae = Self("trae")
    static let qoder = Self("qoder", .lightBacked)
    static let codeBuddy = Self("codebuddy")
    static let cline = Self("cline", .monochrome)
    static let goose = Self("goose", .monochrome)
    static let openRouter = Self("openrouter")
    static let perplexity = Self("perplexity")
    static let xAI = Self("xai", .monochrome)
    static let cohere = Self("cohere", .lightBacked)
    static let miniMax = Self("minimax")
    static let stepFun = Self("stepfun")
    static let baichuan = Self("baichuan")
    static let hunyuan = Self("hunyuan", .lightBacked)
    static let tencent = Self("tencent", .lightBacked)
    static let ibm = Self("ibm", .monochrome)
    static let groq = Self("groq", .monochrome)
    static let replicate = Self("replicate", .monochrome)
    static let together = Self("together")
    static let dify = Self("dify", .lightBacked)
    static let n8n = Self("n8n")
    static let modelContextProtocol = Self("mcp", .monochrome)
    static let notebookLM = Self("notebooklm", .monochrome)
    static let manus = Self("manus", .monochrome)
    static let devin = Self("devin")
    static let replit = Self("replit")
    static let lovable = Self("lovable")
    static let v0 = Self("v0", .monochrome)

    static let all: [Self] = [
        .cursor, .claudeCode, .claude, .codex, .openAI, .antigravity, .openCode, .t3Code, .gemini,
        .kiro, .windsurf, .copilot, .vsCode, .sublimeText, .intelliJ, .xcode, .androidStudio,
        .ollama, .lmStudio, .llamaCpp, .huggingFace, .meta, .qwen, .gemma, .mistral, .deepSeek,
        .microsoft, .nvidia, .moonshot, .zhipu, .flux, .stability, .apple,
        .nodeJS, .python, .java, .typeScript, .javaScript, .rust, .go, .swift, .kotlin, .ruby, .php,
        .c, .cPlusPlus, .cSharp, .dart, .scala, .lua, .perl, .elixir, .haskell, .html, .css, .sass, .bash,
        .docker, .git, .gradle, .maven, .npm, .yarn, .pnpm, .bun, .deno, .nvm, .anaconda, .poetry, .uv,
        .homebrew, .nextJS, .turborepo, .flutter, .react, .vue, .jupyter, .cocoaPods,
        .aws, .googleCloud, .azure, .google, .kubernetes, .helm, .terraform, .vault, .ansible,
        .vercel, .netlify, .heroku, .cloudflare, .supabase, .firebase, .stripe, .sentry, .datadog,
        .postman, .gitHub, .gitLab, .bitbucket, .ngrok, .tailscale, .convex, .wakaTime, .sonarQube,
        .kaggle, .streamlit, .keras, .tensorFlow, .pyTorch, .numPy, .pandas, .sciPy, .matplotlib,
        .scikitLearn, .django, .flask, .fastAPI, .langChain, .tailwind, .esLint, .prettier, .vite,
        .webpack, .esbuild, .svelte, .angular, .nuxt, .electron, .playwright, .cypress, .selenium,
        .puppeteer, .jest, .storybook, .biome, .shadcn, .prisma, .drizzle, .graphQL, .postgres,
        .mySQL, .redis, .mongoDB, .sqlite, .elasticsearch, .kafka, .rabbitMQ, .clickHouse, .cassandra,
        .mariaDB, .oracle, .objectiveC, .r, .julia, .zig, .nim, .clojure, .erlang,
        .ocaml, .fSharp, .visualBasic, .powerShell, .webAssembly, .solidity, .groovy, .astro, .laTeX,
        .markdown, .json, .yaml, .toml, .fish, .zsh, .vim, .neovim, .emacs,
        .tmux, .cmake, .ffmpeg, .openSSL, .hugo, .make, .dotNet, .nginx, .apache,
        .linux, .ubuntu, .debian, .adobe, .photoshop, .illustrator, .premierePro, .afterEffects, .figma,
        .sketch, .notion, .slack, .discord, .telegram, .whatsApp, .signal, .zoom, .spotify,
        .chrome, .firefox, .safari, .brave, .arc, .vivaldi, .opera, .dropbox, .googleDrive,
        .iCloud, .mega, .box, .onePassword, .bitwarden, .obsidian, .raycast, .iTerm2, .warp,
        .ghostty, .alacritty, .zed, .atom, .unity, .unrealEngine, .blender, .godot, .steam,
        .epicGames, .vlc, .plex, .jellyfin, .obsStudio, .daVinciResolve, .audacity, .gimp, .inkscape,
        .krita, .vmware, .virtualBox, .nordVPN, .wireGuard, .openVPN, .gitKraken, .dataGrip, .pyCharm,
        .webStorm, .cLion, .goLand, .phpStorm, .rider, .rubyMine, .jetBrains, .loom, .anki,
        .qBittorrent, .wireshark, .libreOffice, .gitea, .sourcetree, .mpv, .sonarr, .lens, .rStudio,
        .kiloCode, .rooCode, .trae, .qoder, .codeBuddy, .cline, .goose, .openRouter, .perplexity,
        .xAI, .cohere, .miniMax, .stepFun, .baichuan, .hunyuan, .tencent, .ibm, .groq,
        .replicate, .together, .dify, .n8n, .modelContextProtocol, .notebookLM, .manus, .devin, .replit,
        .lovable, .v0
    ]
}
