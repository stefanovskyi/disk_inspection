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

    static let all: [Self] = [
        .cursor, .claudeCode, .claude, .codex, .openAI, .antigravity, .openCode, .t3Code, .gemini,
        .kiro, .windsurf, .copilot, .vsCode, .sublimeText, .intelliJ, .xcode, .androidStudio,
        .ollama, .lmStudio, .llamaCpp, .huggingFace, .meta, .qwen, .gemma, .mistral, .deepSeek,
        .microsoft, .nvidia, .moonshot, .zhipu, .flux, .stability, .apple,
        .nodeJS, .python, .java, .typeScript, .javaScript, .rust, .go, .swift, .kotlin, .ruby, .php,
        .c, .cPlusPlus, .cSharp, .dart, .scala, .lua, .perl, .elixir, .haskell, .html, .css, .sass, .bash,
        .docker, .git, .gradle, .maven, .npm, .yarn, .pnpm, .bun, .deno, .nvm, .anaconda, .poetry, .uv,
        .homebrew, .nextJS, .turborepo, .flutter, .react, .vue, .jupyter, .cocoaPods
    ]
}

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
        (["gpt", "whisper", "openai"], .openAI),
        (["microsoft"], .microsoft)
    ]

    /// Exact, case-sensitive folder names: tools own these conventional locations.
    private static let directoryLogos: [String: BrandLogo] = [
        ".claude": .claudeCode, ".cursor": .cursor, ".cursor-server": .cursor, ".codex": .codex,
        ".antigravity": .antigravity, ".antigravity-ide": .antigravity, ".opencode": .openCode,
        "opencode": .openCode, ".t3": .t3Code, ".gemini": .gemini, ".kiro": .kiro, ".kiro-server": .kiro,
        ".windsurf": .windsurf, ".copilot": .copilot, ".vscode": .vsCode, ".vscode-insiders": .vsCode,
        ".vscode-server": .vsCode, "DerivedData": .xcode, "Xcode": .xcode, "XCTestDevices": .xcode,
        ".android": .androidStudio, ".ollama": .ollama, ".lmstudio": .lmStudio, "huggingface": .huggingFace,
        ".huggingface": .huggingFace,
        "node_modules": .nodeJS, ".npm": .npm, ".nvm": .nvm, ".yarn": .yarn, ".pnpm-store": .pnpm,
        ".bun": .bun, ".deno": .deno, ".next": .nextJS, ".turbo": .turborepo,
        ".venv": .python, "venv": .python, "__pycache__": .python, ".pytest_cache": .python,
        ".mypy_cache": .python, ".ruff_cache": .python, ".tox": .python, ".nox": .python, ".pyenv": .python,
        ".conda": .anaconda, "anaconda3": .anaconda, "miniconda3": .anaconda, "miniforge3": .anaconda,
        "mambaforge": .anaconda, ".ipython": .jupyter, ".jupyter": .jupyter,
        ".m2": .maven, ".gradle": .gradle, ".sdkman": .java,
        ".cargo": .rust, ".rustup": .rust, ".rbenv": .ruby, ".gem": .ruby, ".swiftpm": .swift, ".kotlin": .kotlin,
        ".docker": .docker, ".git": .git, "Homebrew": .homebrew, "homebrew": .homebrew,
        ".cocoapods": .cocoaPods, "CocoaPods": .cocoaPods, ".pub-cache": .dart, ".dart_tool": .dart,
        ".flutter": .flutter, ".idea": .intelliJ
    ]

    /// Application data folders in the Library, shown when the application is not
    /// installed. Elsewhere these names are ordinary folders, such as a project.
    private static let applicationFolderLogos: [String: BrandLogo] = [
        "Claude": .claude, "ChatGPT": .openAI, "Cursor": .cursor, "Antigravity": .antigravity,
        "T3 Code": .t3Code, "Windsurf": .windsurf, "Kiro": .kiro, "Code": .vsCode,
        "Sublime Text": .sublimeText, "JetBrains": .intelliJ, "Ollama": .ollama,
        "LM Studio": .lmStudio, "Docker": .docker
    ]

    private static let directoryExtensionLogos: [String: BrandLogo] = [
        "xcodeproj": .xcode, "xcworkspace": .xcode, "xcarchive": .xcode, "playground": .swift
    ]

    private static let fileNameLogos: [String: BrandLogo] = [
        "Dockerfile": .docker, "package.json": .nodeJS, "Cargo.toml": .rust, "go.mod": .go,
        "pyproject.toml": .python, "Podfile": .cocoaPods, "Gemfile": .ruby, "pom.xml": .maven,
        "build.gradle": .gradle, "build.gradle.kts": .gradle
    ]

    private static let fileExtensionLogos: [String: BrandLogo] = [
        "py": .python, "pyi": .python, "ipynb": .jupyter, "js": .javaScript, "mjs": .javaScript,
        "cjs": .javaScript, "jsx": .react, "ts": .typeScript, "mts": .typeScript, "tsx": .react,
        "vue": .vue, "rs": .rust, "go": .go, "swift": .swift, "java": .java, "jar": .java, "class": .java,
        "kt": .kotlin, "kts": .kotlin, "rb": .ruby, "php": .php, "c": .c, "h": .c, "cc": .cPlusPlus,
        "cpp": .cPlusPlus, "cxx": .cPlusPlus, "hpp": .cPlusPlus, "cs": .cSharp, "dart": .dart,
        "scala": .scala, "lua": .lua, "pl": .perl, "pm": .perl, "ex": .elixir, "exs": .elixir,
        "hs": .haskell, "html": .html, "htm": .html, "css": .css, "scss": .sass, "sass": .sass,
        "sh": .bash, "bash": .bash, "zsh": .bash, "gguf": .llamaCpp
    ]

    static func logo(forApplicationFolderNamed name: String) -> BrandLogo? {
        applicationFolderLogos[name]
    }

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

    static func logo(forItemNamed name: String, isDirectory: Bool) -> BrandLogo? {
        let pathExtension = (name as NSString).pathExtension.lowercased()
        if isDirectory {
            return directoryLogos[name] ?? directoryExtensionLogos[pathExtension]
        }
        return fileNameLogos[name] ?? fileExtensionLogos[pathExtension]
    }
}

/// Where to read the real icon of an application from Launch Services.
enum ApplicationIconSource: Hashable, Sendable {
    case bundle(URL)
    case bundleIdentifier(String)
    case applicationNamed(String)
}

/// How a scanned file or folder is identified in storage lists.
enum StorageItemIcon: Equatable, Sendable {
    /// The application's real icon, or the logo when that application is not installed.
    case application(ApplicationIconSource, fallback: BrandLogo?)
    case brand(BrandLogo)
    case generic

    /// Library folders named after the application that owns their contents.
    private static let applicationNamedParents: Set<String> = ["Application Support", "Caches", "Logs"]
    private static let bundleIdentifiedParents: Set<String> = [
        "Application Scripts", "Application Support", "Caches", "Containers", "HTTPStorages",
        "Logs", "Preferences", "Saved Application State", "WebKit"
    ]
    private static let bundleIdentifierSuffixes = [".plist", ".savedState", ".binarycookies"]
    /// Application Support names that differ from the application's name.
    private static let applicationNameAliases = ["Code": "Visual Studio Code"]

    static func resolve(url: URL, isDirectory: Bool) -> Self {
        let name = url.lastPathComponent
        let parent = url.deletingLastPathComponent().lastPathComponent
        let brand = BrandLogoCatalog.logo(forItemNamed: name, isDirectory: isDirectory)

        if isDirectory, name.lowercased().hasSuffix(".app") {
            return .application(.bundle(url), fallback: brand)
        }
        if bundleIdentifiedParents.contains(parent), let identifier = bundleIdentifier(in: name) {
            return .application(.bundleIdentifier(identifier), fallback: brand)
        }
        if isDirectory, applicationNamedParents.contains(parent), !name.hasPrefix(".") {
            return .application(
                .applicationNamed(applicationNameAliases[name] ?? name),
                fallback: BrandLogoCatalog.logo(forApplicationFolderNamed: name) ?? brand
            )
        }
        return brand.map(Self.brand) ?? .generic
    }

    private static func bundleIdentifier(in name: String) -> String? {
        var identifier = name
        for suffix in bundleIdentifierSuffixes where identifier.hasSuffix(suffix) {
            identifier.removeLast(suffix.count)
        }
        let components = identifier.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 3, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        let isReverseDNS = identifier.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "_")
        }
        return isReverseDNS ? identifier : nil
    }
}
