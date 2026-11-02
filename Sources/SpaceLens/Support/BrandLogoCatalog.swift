import Foundation

enum BrandLogoCatalog {
    /// Whole words in a developer-storage location name, checked in order so a
    /// specific tool wins over its language: "Gradle JDKs" is Gradle, not Java.
    private static let storageNameRules: [(terms: Set<String>, logo: BrandLogo)] = [
        (["claude"], .claudeCode),
        (["cursor"], .cursor),
        (["codex"], .codex),
        (["antigravity"], .antigravity),
        (["gemini"], .gemini),
        (["kiro"], .kiro),
        (["windsurf"], .windsurf),
        (["vs code"], .vsCode),
        (["opencode"], .openCode),
        (["t3 code"], .t3Code),
        (["gradle"], .gradle),
        (["maven"], .maven),
        (["npm"], .npm),
        (["yarn"], .yarn),
        (["pnpm"], .pnpm),
        (["bun"], .bun),
        (["nvm"], .nvm),
        (["next"], .nextJS),
        (["turbo"], .turborepo),
        (["deno"], .deno),
        (["node"], .nodeJS),
        (["poetry"], .poetry),
        (["uv"], .uv),
        (["conda", "miniconda3", "anaconda3", "miniforge3", "mambaforge"], .anaconda),
        (["python", "pip", "pyenv", "tox", "nox", "venv", "pycache", "pytest", "mypy", "ruff"], .python),
        (["java", "jdk", "jdks", "openjdk", "sdkman"], .java),
        (["homebrew"], .homebrew)
    ]

    /// Fragments of a model name that identify its publisher, checked in order.
    private static let modelNameRules: [(fragments: [String], logo: BrandLogo)] = [
        (["qwen"], .qwen),
        (["gemma"], .gemma),
        (["gemini"], .gemini),
        (["llama"], .meta),
        (["mistral", "mixtral", "codestral", "devstral", "pixtral"], .mistral),
        (["deepseek"], .deepSeek),
        (["nemotron", "nvidia"], .nvidia),
        (["kimi", "moonshot"], .moonshot),
        (["glm"], .zhipu),
        (["flux"], .flux),
        (["stable-diffusion", "stable_diffusion", "stabilityai", "sdxl"], .stability),
        (["grok"], .xAI),
        (["command-r", "cohere"], .cohere),
        (["minimax"], .miniMax),
        (["stepfun"], .stepFun),
        (["baichuan"], .baichuan),
        (["hunyuan"], .hunyuan),
        (["granite", "ibm-"], .ibm),
        (["gpt", "whisper", "openai"], .openAI),
        (["microsoft"], .microsoft)
    ]

    /// Exact, case-sensitive folder names: tools own these conventional locations.
    private static let directoryLogos: [String: BrandLogo] = [
        "opencode": .openCode, "DerivedData": .xcode, "Xcode": .xcode, "XCTestDevices": .xcode,
        "CoreSimulator": .xcode, "huggingface": .huggingFace, "node_modules": .nodeJS,
        "venv": .python, "site-packages": .python, "__pycache__": .python,
        "anaconda3": .anaconda, "miniconda3": .anaconda, "miniforge3": .anaconda, "mambaforge": .anaconda,
        "Homebrew": .homebrew, "homebrew": .homebrew, "CocoaPods": .cocoaPods,
        "google-cloud-sdk": .googleCloud, "awscli-bundle": .aws, "whisper-models": .openAI,
        "PycharmProjects": .pyCharm, "DataGripProjects": .dataGrip, "StudioProjects": .androidStudio,
        "WebstormProjects": .webStorm, "GolandProjects": .goLand, "CLionProjects": .cLion,
        "PhpstormProjects": .phpStorm, "RiderProjects": .rider, "RubymineProjects": .rubyMine,
        "IdeaProjects": .intelliJ
    ]

    /// Folders that only identify a product directly inside the home directory.
    private static let homeFolderLogos: [String: BrandLogo] = [
        "go": .go, "Dropbox": .dropbox, "Google Drive": .googleDrive, "MEGA": .mega,
        "Postman": .postman, "Unity": .unity, "sonarqube": .sonarQube
    ]

    private static let directoryExtensionLogos: [String: BrandLogo] = [
        "xcodeproj": .xcode, "xcworkspace": .xcode, "xcarchive": .xcode, "playground": .swift
    ]

    private static let fileNameLogos: [String: BrandLogo] = [
        "Dockerfile": .docker, "docker-compose.yml": .docker, "docker-compose.yaml": .docker,
        ".dockerignore": .docker, "package.json": .nodeJS, "package-lock.json": .npm, ".npmrc": .npm,
        "yarn.lock": .yarn, "pnpm-lock.yaml": .pnpm, "bun.lock": .bun, "bun.lockb": .bun, ".node_path": .nodeJS,
        "Cargo.toml": .rust, "Cargo.lock": .rust, "go.mod": .go, "go.sum": .go, "pyproject.toml": .python,
        "requirements.txt": .python, ".python_history": .python, ".condarc": .anaconda, "uv.lock": .uv,
        "poetry.lock": .poetry, "Podfile": .cocoaPods, "Podfile.lock": .cocoaPods, "Gemfile": .ruby,
        "Gemfile.lock": .ruby, "pom.xml": .maven, "build.gradle": .gradle, "build.gradle.kts": .gradle,
        "settings.gradle": .gradle, "CMakeLists.txt": .cmake, "Makefile": .make, ".gitconfig": .git,
        ".gitignore": .git, ".gitattributes": .git, ".gitlab-ci.yml": .gitLab, ".psql_history": .postgres,
        ".mysql_history": .mySQL, ".dbshell": .mongoDB, ".viminfo": .vim, ".vimrc": .vim, ".tmux.conf": .tmux,
        ".bashrc": .bash, ".bash_profile": .bash, ".bash_history": .bash, ".profile": .bash,
        ".zshrc": .zsh, ".zshenv": .zsh, ".zprofile": .zsh, ".zsh_history": .zsh, ".zlogin": .zsh,
        ".claude.json": .claudeCode, "CLAUDE.md": .claudeCode, "next.config.js": .nextJS,
        "next.config.mjs": .nextJS, "next.config.ts": .nextJS, "vite.config.ts": .vite, "vite.config.js": .vite,
        "tailwind.config.js": .tailwind, "tailwind.config.ts": .tailwind, "tsconfig.json": .typeScript,
        "Package.swift": .swift, ".Rhistory": .r, ".vault-token": .vault
    ]

    private static let fileExtensionLogos: [String: BrandLogo] = [
        "py": .python, "pyi": .python, "pyc": .python, "pyw": .python, "whl": .python, "ipynb": .jupyter,
        "js": .javaScript, "mjs": .javaScript, "cjs": .javaScript, "jsx": .react, "ts": .typeScript,
        "mts": .typeScript, "tsx": .react, "vue": .vue, "svelte": .svelte, "astro": .astro,
        "rs": .rust, "go": .go, "swift": .swift, "java": .java, "jar": .java, "class": .java,
        "kt": .kotlin, "kts": .kotlin, "groovy": .groovy, "gradle": .gradle, "rb": .ruby, "gem": .ruby,
        "php": .php, "c": .c, "h": .c, "cc": .cPlusPlus, "cpp": .cPlusPlus, "cxx": .cPlusPlus, "hpp": .cPlusPlus,
        "m": .objectiveC, "mm": .objectiveC, "cs": .cSharp, "csproj": .dotNet, "sln": .dotNet, "fs": .fSharp,
        "fsx": .fSharp, "vb": .visualBasic, "dart": .dart, "scala": .scala, "lua": .lua, "pl": .perl, "pm": .perl,
        "ex": .elixir, "exs": .elixir, "erl": .erlang, "hs": .haskell, "ml": .ocaml, "clj": .clojure,
        "cljs": .clojure, "r": .r, "rmd": .r, "rds": .r, "rproj": .rStudio, "jl": .julia, "zig": .zig, "nim": .nim,
        "sol": .solidity, "wasm": .webAssembly, "tex": .laTeX, "bib": .laTeX, "ps1": .powerShell,
        "html": .html, "htm": .html, "css": .css, "scss": .sass, "sass": .sass, "md": .markdown, "mdx": .markdown,
        "markdown": .markdown, "json": .json, "yml": .yaml, "yaml": .yaml, "toml": .toml,
        "graphql": .graphQL, "gql": .graphQL, "prisma": .prisma, "tf": .terraform, "tfvars": .terraform,
        "tfstate": .terraform, "sqlite": .sqlite, "sqlite3": .sqlite, "dump": .postgres,
        "sh": .bash, "bash": .bash, "zsh": .zsh, "fish": .fish, "vim": .vim,
        "gguf": .llamaCpp, "ggml": .llamaCpp, "safetensors": .huggingFace, "pt": .pyTorch, "pth": .pyTorch,
        "keras": .keras, "psd": .photoshop, "psb": .photoshop, "ai": .illustrator, "prproj": .premierePro,
        "aep": .afterEffects, "fig": .figma, "sketch": .sketch, "blend": .blender,
        "unity": .unity, "unitypackage": .unity, "uproject": .unrealEngine
    ]

    /// Libraries by package name. Package folders only match this table, so an npm
    /// package that happens to be called `signal` or `box` keeps a generic icon.
    private static let packageLogos: [String: BrandLogo] = logoTable([
        (.react, ["react", "react-dom", "@react"]),
        (.nextJS, ["next", "@next", "next-swc", "nextjs-nodejs", "create-next-app-nodejs"]),
        (.turborepo, ["turbo", "turborepo"]),
        (.typeScript, ["typescript", "@types", "tsc", "ts-node"]),
        (.tailwind, ["tailwindcss", "@tailwindcss"]),
        (.esLint, ["eslint", "@eslint"]),
        (.prettier, ["prettier"]),
        (.vite, ["vite", "@vitejs"]),
        (.webpack, ["webpack"]),
        (.esbuild, ["esbuild", "@esbuild"]),
        (.svelte, ["svelte", "@sveltejs"]),
        (.angular, ["angular", "@angular"]),
        (.vue, ["vue", "@vue"]),
        (.nuxt, ["nuxt", "@nuxt"]),
        (.astro, ["astro"]),
        (.electron, ["electron", "@electron", "electron-builder"]),
        (.playwright, ["playwright", "@playwright", "ms-playwright", "ms-playwright-go"]),
        (.cypress, ["cypress"]),
        (.selenium, ["selenium", "selenium-webdriver"]),
        (.puppeteer, ["puppeteer"]),
        (.jest, ["jest", "@jest"]),
        (.storybook, ["storybook", "@storybook"]),
        (.biome, ["biome", "@biomejs", "dev.biomejs.biome"]),
        (.shadcn, ["shadcn"]),
        (.prisma, ["prisma", "@prisma"]),
        (.drizzle, ["drizzle", "drizzle-orm", "drizzle-kit", "drizzle-studio"]),
        (.graphQL, ["graphql"]),
        (.sass, ["sass"]),
        (.streamlit, ["streamlit"]),
        (.keras, ["keras"]),
        (.tensorFlow, ["tensorflow"]),
        (.pyTorch, ["torch", "pytorch"]),
        (.numPy, ["numpy"]),
        (.pandas, ["pandas"]),
        (.sciPy, ["scipy"]),
        (.matplotlib, ["matplotlib"]),
        (.scikitLearn, ["sklearn", "scikit-learn"]),
        (.django, ["django"]),
        (.flask, ["flask"]),
        (.fastAPI, ["fastapi"]),
        (.openAI, ["openai", "tiktoken"]),
        (.huggingFace, ["transformers", "diffusers", "huggingface_hub", "@huggingface"]),
        (.langChain, ["langchain", "@langchain"]),
        (.modelContextProtocol, ["mcp", "fastmcp", "@modelcontextprotocol"]),
        (.electron, ["electron", "@electron", "electron-builder"]),
        (.supabase, ["supabase", "@supabase"]),
        (.vercel, ["vercel", "@vercel"]),
        (.firebase, ["firebase", "firebase-tools", "firebase-admin", "@firebase"]),
        (.stripe, ["stripe", "@stripe"]),
        (.sentry, ["@sentry", "sentry-sdk"]),
        (.cloudflare, ["wrangler", "@cloudflare"]),
        (.aws, ["boto3", "botocore", "aws-sdk", "@aws-sdk"]),
        (.googleCloud, ["@google-cloud"]),
        (.convex, ["convex"]),
        (.jupyter, ["jupyter", "jupyterlab", "ipykernel", "ipython"])
    ])

    private static func logoTable(_ groups: [(BrandLogo, [String])]) -> [String: BrandLogo] {
        var logos: [String: BrandLogo] = [:]
        for (logo, names) in groups {
            for name in names { logos[name] = logo }
        }
        return logos
    }

    /// Products by normalized name. These names are too common to match anywhere,
    /// so callers only consult them where a tool's data is expected.
    private static let productLogos: [String: BrandLogo] = logoTable([
            // AI coding tools and services.
            (.claudeCode, ["claude", "claude-code", "claude-cli-nodejs"]),
            (.claude, ["claude-3p"]),
            (.cursor, ["cursor", "cursor-agent", "cursor-compile-cache", "cursor-server", "cursor-tutor"]),
            (.codex, ["codex", "codex-runtimes"]),
            (.antigravity, ["antigravity", "antigravity-ide", "antigravity-updater"]),
            (.openCode, ["opencode"]),
            (.t3Code, ["t3", "t3code", "t3code-v2", "t3 code"]),
            (.gemini, ["gemini", "gemini-cli"]),
            (.kiro, ["kiro", "kiro-server"]),
            (.windsurf, ["windsurf", "codeium"]),
            (.copilot, ["copilot", "github-copilot"]),
            (.kiloCode, ["kilo", "kilocode"]),
            (.rooCode, ["roo", "roo-code"]),
            (.trae, ["trae"]),
            (.qoder, ["qoder"]),
            (.codeBuddy, ["codebuddy"]),
            (.cline, ["cline"]),
            (.goose, ["goose"]),
            (.openRouter, ["openrouter"]),
            (.replit, ["replit"]),
            (.lovable, ["lovable"]),
            (.devin, ["devin"]),
            (.modelContextProtocol, ["mcp", "mcp-auth", "fastmcp", "@modelcontextprotocol"]),
            (.openAI, ["openai", "chatgpt", "chatgpthelper", "whisper", "tiktoken"]),
            (.perplexity, ["perplexity", "perplexity-ai"]),
            (.ollama, ["ollama"]),
            (.lmStudio, ["lmstudio", "lm-studio", "lm studio", "lmstudio-home-pointer"]),
            (.llamaCpp, ["llama.cpp", "llama-cpp", "llama-cpp-python"]),
            (.huggingFace, ["huggingface", "hf", "transformers", "diffusers", "@huggingface"]),
            (.langChain, ["langchain", "@langchain"]),
            (.nvidia, ["nvidia", "nvidia corporation"]),

            // Editors, IDEs, and terminals.
            (.vsCode, ["vscode", "code", "vscode-insiders", "vscode-server", "vscode-shared", "vscode-ripgrep", "vscode-sqltools"]),
            (.sublimeText, ["sublime text", "sublime-text"]),
            (.jetBrains, ["jetbrains"]),
            (.intelliJ, ["idea", "intellij"]),
            (.pyCharm, ["pycharm"]),
            (.dataGrip, ["datagrip"]),
            (.webStorm, ["webstorm"]),
            (.androidStudio, ["android", "android open source project", "android-platform-tools"]),
            (.xcode, ["xcode", "dvtdownloads", "developerdiskimages"]),
            (.vim, ["vim"]),
            (.neovim, ["nvim", "neovim"]),
            (.emacs, ["emacs", "emacs.d"]),
            (.zed, ["zed"]),
            (.atom, ["atom"]),
            (.iTerm2, ["iterm2", "iterm"]),
            (.warp, ["warp", "warp-terminal", "warp-preview"]),
            (.ghostty, ["ghostty"]),
            (.alacritty, ["alacritty"]),
            (.rStudio, ["rstudio", "rstudio-desktop"]),
            (.jupyter, ["jupyter", "ipython", "ipynb_checkpoints"]),

            // Languages, runtimes, and package managers.
            (.nodeJS, ["node", "nodejs", "node-gyp", "node_path"]),
            (.npm, ["npm", "npm-global"]),
            (.yarn, ["yarn"]),
            (.pnpm, ["pnpm", "pnpm-store"]),
            (.bun, ["bun"]),
            (.deno, ["deno"]),
            (.nvm, ["nvm"]),
            (.python, ["python", "python3", "pip", "pipx", "pyenv", "pyenv-repository", "venv", "python entry points", "pythonwrapper", "idlerc", "pytest_cache", "mypy_cache", "ruff_cache", "tox", "nox"]),
            (.anaconda, ["conda", "anaconda", "anaconda-navigator", "continuum", "binstar"]),
            (.uv, ["uv"]),
            (.poetry, ["poetry", "pypoetry"]),
            (.java, ["java", "openjdk", "javasharedresources", "jreinstaller", "oracle_jre_usage", "sdkman"]),
            (.maven, ["m2", "maven"]),
            (.gradle, ["gradle"]),
            (.kotlin, ["kotlin", "konan"]),
            (.rust, ["rust", "cargo", "rustup"]),
            (.go, ["go", "go-build", "goimports", "golang"]),
            (.swift, ["swift", "swiftpm", "org.swift.swiftpm"]),
            (.ruby, ["ruby", "rbenv", "gem", "rvm"]),
            (.php, ["php", "composer"]),
            (.dotNet, ["net", "dotnet", "aspnet", "nuget"]),
            (.dart, ["dart", "dart_tool", "pub-cache"]),
            (.flutter, ["flutter", "flutter_engine"]),
            (.r, ["r"]),
            (.julia, ["julia"]),
            (.zig, ["zig"]),
            (.lua, ["lua", "luarocks"]),
            (.perl, ["perl"]),
            (.elixir, ["elixir", "mix", "hex"]),
            (.erlang, ["erlang"]),
            (.haskell, ["haskell", "ghc", "cabal", "stack"]),
            (.ocaml, ["ocaml", "opam"]),
            (.clojure, ["clojure"]),
            (.bash, ["bash", "bash_sessions"]),
            (.zsh, ["zsh", "zsh_sessions", "oh-my-zsh"]),
            (.fish, ["fish"]),
            (.powerShell, ["powershell"]),

            // Cloud services and infrastructure.
            (.aws, ["aws", "awscli", "aws-cli", "boto", "aws-cloudformation-languageserver", "aws-elastic-beanstalk-cli-setup"]),
            (.azure, ["azure", "azure-cli", "azure-functions-core-tools"]),
            (.googleCloud, ["gcloud", "google-cloud-sdk", "google-cloud-tools-java", "cloud-code"]),
            (.kubernetes, ["kube", "kubernetes", "kubernetes-cli", "kubectl", "kubectx", "minikube"]),
            (.helm, ["helm"]),
            (.terraform, ["terraform", "terraform.d"]),
            (.vault, ["vault"]),
            (.ansible, ["ansible"]),
            (.docker, ["docker", "docker desktop", "docker-compose", "colima"]),
            (.vercel, ["vercel", "@vercel", "vercel-plugin"]),
            (.netlify, ["netlify"]),
            (.heroku, ["heroku"]),
            (.cloudflare, ["cloudflare", "wrangler", "@cloudflare"]),
            (.supabase, ["supabase", "@supabase"]),
            (.firebase, ["firebase", "firebase-tools"]),
            (.stripe, ["stripe", "@stripe"]),
            (.sentry, ["sentry", "@sentry", "sentrycrash", "sentry_crash"]),
            (.datadog, ["datadog", "datadog-agent"]),
            (.postman, ["postman"]),
            (.gitHub, ["github", "gh", "@github"]),
            (.gitLab, ["gitlab", "glab", "glab-cli", "gitlab-runner"]),
            (.bitbucket, ["bitbucket"]),
            (.git, ["git", "jgit"]),
            (.gitKraken, ["gitkraken", "gitkrakencli", "gk"]),
            (.sourcetree, ["sourcetree"]),
            (.ngrok, ["ngrok"]),
            (.tailscale, ["tailscale", "tailscale-app"]),
            (.convex, ["convex"]),
            (.wakaTime, ["wakatime", "wakatime-internal"]),
            (.sonarQube, ["sonarqube", "sonarlint"]),
            (.kaggle, ["kaggle"]),
            (.n8n, ["n8n"]),

            // Databases and system tools.
            (.postgres, ["postgres", "postgresql", "libpq", "psequel"]),
            (.mySQL, ["mysql", "mysql-client", "mysql workbench"]),
            (.redis, ["redis", "redis-stack"]),
            (.mongoDB, ["mongodb", "mongodb compass", "mongosh", "mongodb-database-tools"]),
            (.sqlite, ["sqlite", "sqlite3"]),
            (.elasticsearch, ["elasticsearch"]),
            (.kafka, ["kafka"]),
            (.rabbitMQ, ["rabbitmq"]),
            (.clickHouse, ["clickhouse"]),
            (.cassandra, ["cassandra"]),
            (.mariaDB, ["mariadb"]),
            (.oracle, ["oracle"]),
            (.homebrew, ["homebrew", "brew"]),
            (.cmake, ["cmake"]),
            (.make, ["make"]),
            (.ffmpeg, ["ffmpeg"]),
            (.openSSL, ["openssl"]),
            (.hugo, ["hugo", "hugo_cache"]),
            (.tmux, ["tmux"]),
            (.nginx, ["nginx"]),
            (.apache, ["apache", "httpd"]),

            // Applications, shown when the application itself is not installed.
            (.adobe, ["adobe"]),
            (.microsoft, ["microsoft", "microsoft edge"]),
            (.google, ["google"]),
            (.apple, ["apple"]),
            (.chrome, ["chrome", "chromium", "google chrome"]),
            (.firefox, ["firefox", "mozilla"]),
            (.safari, ["safari"]),
            (.brave, ["brave", "bravesoftware"]),
            (.arc, ["arc"]),
            (.vivaldi, ["vivaldi"]),
            (.opera, ["opera"]),
            (.slack, ["slack"]),
            (.discord, ["discord"]),
            (.telegram, ["telegram"]),
            (.whatsApp, ["whatsapp"]),
            (.signal, ["signal"]),
            (.zoom, ["zoom", "zoomupdater", "zoomphone", "zoom.us"]),
            (.spotify, ["spotify"]),
            (.notion, ["notion"]),
            (.obsidian, ["obsidian"]),
            (.figma, ["figma"]),
            (.sketch, ["sketch"]),
            (.raycast, ["raycast"]),
            (.dropbox, ["dropbox"]),
            (.googleDrive, ["google drive", "google_drive", "googledrive"]),
            (.iCloud, ["icloud", "clouddocs", "mobile documents"]),
            (.mega, ["mega", "mega limited"]),
            (.box, ["box", "box sync"]),
            (.onePassword, ["1password"]),
            (.bitwarden, ["bitwarden"]),
            (.unity, ["unity", "unity hub", "unityhub"]),
            (.unrealEngine, ["unreal engine", "unrealengine"]),
            (.blender, ["blender"]),
            (.godot, ["godot"]),
            (.steam, ["steam"]),
            (.epicGames, ["epic", "epic games"]),
            (.vlc, ["vlc"]),
            (.plex, ["plex", "plex media server"]),
            (.jellyfin, ["jellyfin", "jellyfin media player"]),
            (.obsStudio, ["obs", "obs-studio"]),
            (.daVinciResolve, ["davinci resolve", "blackmagic design", "blackmagic raw", "blackmagic proxy generator lite"]),
            (.audacity, ["audacity"]),
            (.gimp, ["gimp"]),
            (.inkscape, ["inkscape"]),
            (.krita, ["krita"]),
            (.vmware, ["vmware", "vmware fusion"]),
            (.virtualBox, ["virtualbox"]),
            (.nordVPN, ["nordvpn"]),
            (.wireGuard, ["wireguard"]),
            (.openVPN, ["openvpn", "openvpn connect"]),
            (.loom, ["loom"]),
            (.anki, ["anki", "ankiprogramfiles"]),
            (.qBittorrent, ["qbittorrent"]),
            (.wireshark, ["wireshark"]),
            (.libreOffice, ["libreoffice"]),
            (.mpv, ["mpv"]),
            (.sonarr, ["sonarr"]),
            (.lens, ["lens", "openlens", "k8slens"])
    ]).merging(packageLogos) { product, _ in product }

    /// Product families whose many helpers and settings folders share a name prefix.
    private static let productFamilyPrefixes: [(prefix: String, logo: BrandLogo)] = [
        ("adobe", .adobe), ("microsoft", .microsoft), ("google", .google), ("docker", .docker), ("jetbrains", .jetBrains)
    ]

    /// Who publishes an application, by the leading components of its bundle identifier.
    private static let bundleVendorLogos: [String: BrandLogo] = [
        "com.adobe": .adobe, "adobe": .adobe, "com.microsoft": .microsoft, "com.google": .google,
        "com.apple": .apple, "com.docker": .docker, "com.openai": .openAI, "com.openai.codex": .codex,
        "com.anthropic": .claude, "com.jetbrains": .jetBrains, "com.github": .gitHub,
        "com.todesktop.230313mzl4w4u92": .cursor, "com.tinyspeck": .slack, "com.hnc.discord": .discord,
        "ru.keepcoder": .telegram, "net.whatsapp": .whatsApp, "org.whispersystems": .signal, "us.zoom": .zoom,
        "com.spotify": .spotify, "notion.id": .notion, "md.obsidian": .obsidian, "com.figma": .figma,
        "com.bohemiancoding": .sketch, "com.raycast": .raycast, "dev.warp": .warp, "com.googlecode.iterm2": .iTerm2,
        "com.postmanlabs": .postman, "com.vercel": .vercel, "io.sentry": .sentry, "org.swift": .swift,
        "dev.biomejs": .biome, "dev.zed": .zed, "com.getdropbox": .dropbox, "com.dropbox": .dropbox,
        "mega": .mega, "org.mozilla": .firefox, "com.brave": .brave, "company.thebrowser": .arc,
        "com.operasoftware": .opera, "com.vivaldi": .vivaldi, "io.tailscale": .tailscale, "org.jellyfin": .jellyfin,
        "tv.plex": .plex, "com.plexapp": .plex, "org.videolan": .vlc, "com.blackmagic-design": .daVinciResolve,
        "com.obsproject": .obsStudio, "com.1password": .onePassword, "com.agilebits": .onePassword,
        "com.bitwarden": .bitwarden, "org.libreoffice": .libreOffice, "ai.perplexity": .perplexity,
        "com.unity3d": .unity, "unity": .unity, "com.epicgames": .epicGames, "com.valvesoftware": .steam,
        "org.python": .python, "com.oracle": .oracle, "com.datadoghq": .datadog,
        "com.sublimetext": .sublimeText, "org.wireshark": .wireshark, "org.blender": .blender,
        "com.nordvpn": .nordVPN, "net.openvpn": .openVPN
    ]

    /// Apple Developer team identifiers on Group Containers that have no bundle identifier.
    private static let teamLogos: [String: BrandLogo] = [
        "UBF8T346G9": .microsoft, "EQHXZ8M8AV": .google, "JQ525L2MZD": .adobe, "G7HH3F8CAK": .dropbox
    ]

    static func logo(forStorageLocationNamed name: String) -> BrandLogo? {
        let words = name.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        let phrase = " \(words.joined(separator: " ")) "
        return storageNameRules.first { rule in
            rule.terms.contains { phrase.contains(" \($0) ") }
        }?.logo
    }

    static func logo(forModelNamed name: String) -> BrandLogo? {
        let lowercased = name.lowercased()
        if let logo = modelNameRules.first(where: { rule in
            rule.fragments.contains { lowercased.contains($0) }
        })?.logo {
            return logo
        }
        // Phi is too short to match as a fragment: "sapphire" is not a Microsoft model.
        let isPhi = lowercased.split { !$0.isLetter && !$0.isNumber }.contains { word in
            word == "phi" || (word.hasPrefix("phi") && word.dropFirst(3).allSatisfy(\.isNumber))
        }
        return isPhi ? .microsoft : nil
    }

    /// Conventional names that identify a tool wherever they appear.
    static func logo(forItemNamed name: String, isDirectory: Bool) -> BrandLogo? {
        let pathExtension = (name as NSString).pathExtension.lowercased()
        if isDirectory {
            return directoryLogos[name] ?? directoryExtensionLogos[pathExtension]
        }
        if name.hasPrefix(".zcompdump") { return .zsh }
        return fileNameLogos[name] ?? fileExtensionLogos[pathExtension]
    }

    static func logo(forHomeFolderNamed name: String) -> BrandLogo? {
        homeFolderLogos[name]
    }

    /// A product by folder name, ignoring case, a leading dot, and any version:
    /// ".aws", "Sublime Text 3", "python@3.14", and "Python 3.12" all match.
    static func logo(forProductNamed name: String) -> BrandLogo? {
        var normalized = name.lowercased()
        if normalized.hasPrefix(".") { normalized.removeFirst() }
        if normalized.hasSuffix(".localized") { normalized.removeLast(".localized".count) }
        if let logo = productLogos[normalized] { return logo }

        if let at = normalized.firstIndex(of: "@"), at != normalized.startIndex {
            normalized = String(normalized[..<at])
        }
        let versionless = normalized.replacingOccurrences(
            of: #"[-_ ]?v?[0-9][0-9.]*$"#,
            with: "",
            options: .regularExpression
        )
        if let logo = productLogos[versionless] { return logo }
        return productFamilyPrefixes.first { normalized.hasPrefix($0.prefix) }?.logo
    }

    /// A library inside `node_modules` or `site-packages`, or an npm scope.
    static func logo(forPackageNamed name: String) -> BrandLogo? {
        packageLogos[name.lowercased()]
    }

    /// The publisher of a bundle identifier, using its most specific known prefix.
    static func logo(forBundleIdentifier identifier: String) -> BrandLogo? {
        var components = identifier.lowercased().split(separator: ".")
        while !components.isEmpty {
            if let logo = bundleVendorLogos[components.joined(separator: ".")] { return logo }
            components.removeLast()
        }
        return nil
    }

    static func logo(forTeamIdentifier identifier: String) -> BrandLogo? {
        teamLogos[identifier]
    }
}
