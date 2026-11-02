import Foundation

/// The static text behind `StorageItemDescription`. Say what the location is, what
/// fills it, and what deleting it costs, for any Mac, in about two sentences.
enum StorageItemDescriptionCatalog {
    static let homeFolder = StorageItemDescription.keep(
        "A user's home folder: personal files, app data in Library, and hidden tool folders. Review what is inside item by item."
    )
    static let application = StorageItemDescription.review(
        "An application bundle holding the program and its resources. Move it to the Trash to uninstall; its data stays in Library until removed separately."
    )
    static let builtInApplication = StorageItemDescription.keep(
        "An app built into macOS, stored on the protected system volume. It cannot be removed and does not use your personal storage."
    )

    /// Exact locations on the startup disk.
    static let absolutePaths: [String: StorageItemDescription] = [
        "/": .keep("The startup disk: your files, apps, and macOS. The scanned total can differ from used space because of APFS clones, snapshots, and protected items."),

        // MARK: Top level
        "/Applications": .review("Apps installed for all users. Size comes from bundled runtimes and resources, and Xcode alone takes many gigabytes. Uninstall by moving an app to the Trash."),
        "/Library": .keep("System-wide support files shared by all users: app data, fonts, drivers, and background helpers. Separate from the personal Library in each home folder."),
        "/System": .keep("macOS itself, on a sealed read-only volume. Its size is fixed by the macOS version and it cannot be changed."),
        "/Users": .keep("Home folders of every user on this Mac. This is usually the largest folder and holds nearly all personal data."),
        "/Users/Shared": .review("Files shared between all users on this Mac. Some apps also store large content here, such as audio libraries and game data."),
        "/Volumes": .keep("Mount points of connected disks, disk images, and network shares. Its contents live on those disks, not on the startup disk."),
        "/private": .keep("Low-level macOS data behind /var, /tmp, and /etc: temporary files, system databases, logs, and swap. macOS manages it."),
        "/usr": .keep("Unix programs and libraries that ship with macOS, on the sealed system volume. Only /usr/local inside it holds software you installed."),
        "/bin": .keep("Essential Unix commands that ship with macOS. Protected and required for the system to work."),
        "/sbin": .keep("Essential system administration commands that ship with macOS. Protected and required for the system to work."),
        "/etc": .keep("System configuration files such as hosts and sudoers. Small but critical; edit only when you know the exact change."),
        "/var": .keep("Variable system data: logs, databases, temporary files, and swap. macOS manages it."),
        "/tmp": .keep("Temporary files of running programs, cleared on restart. Restart instead of deleting, because running programs may still use them."),
        "/opt": .review("Optional software installed outside macOS, most often Homebrew on Apple silicon. Removing it uninstalls those tools."),
        "/cores": .safe("Crash memory dumps, written only if core dumps are enabled. Each can reach many gigabytes and is useful only for debugging that crash."),
        "/dev": .keep("Virtual files representing hardware devices. They use no real disk space."),
        "/home": .keep("A macOS automount point, normally empty. It uses no disk space and is unrelated to the home folders in /Users."),

        // MARK: /System
        "/System/Applications": .keep("Apps built into macOS, such as Mail, Photos, and Music. They live on the protected system volume and cannot be removed."),
        "/System/Library": .keep("The frameworks, drivers, fonts, and services that make up macOS. Protected and replaced by system updates."),
        "/System/Library/AssetsV2": .keep("On-demand assets macOS downloads, such as language data and on-device AI models. macOS adds and removes them as needed."),
        "/System/Library/Caches": .keep("Caches for macOS system services. macOS maintains them itself."),
        "/System/Volumes": .keep("Hidden APFS volumes that form the startup disk: your data, swap, recovery, and update files. SpaceLens scans your data through its regular paths."),
        "/System/Volumes/VM": .keep("Swap files and the sleep image. Size follows memory pressure and shrinks after a restart."),
        "/System/Volumes/Preboot": .keep("Files macOS needs to start up and unlock the disk. Damage here can prevent the Mac from booting."),
        "/System/Volumes/Recovery": .keep("The macOS Recovery system, used to repair or reinstall macOS."),
        "/System/Volumes/Update": .keep("Temporary working space for macOS updates. macOS cleans it after an update finishes."),
        "/System/Cryptexes": .keep("Signed macOS components that update separately from the sealed system, such as Safari and security responses."),
        "/System/iOSSupport": .keep("Frameworks that let iPad-style apps run on the Mac. Part of macOS."),

        // MARK: /usr and /opt
        "/usr/local": .review("Software you or an installer added outside macOS, including Homebrew on Intel Macs. Removing items here uninstalls those tools."),
        "/usr/local/Cellar": .review("Installed Homebrew formulae, including old versions. Run brew cleanup to remove old versions and brew uninstall for the rest."),
        "/usr/local/Caskroom": .review("Records of apps installed with Homebrew Cask. Use brew uninstall --cask rather than deleting by hand."),
        "/opt/homebrew": .review("Homebrew and everything it installed on Apple silicon. Grows with each formula and its old versions. Run brew cleanup rather than deleting by hand."),
        "/opt/homebrew/Cellar": .review("Installed Homebrew formulae, including old versions. Run brew cleanup to remove old versions and brew uninstall for the rest."),
        "/opt/homebrew/Caskroom": .review("Records of apps installed with Homebrew Cask. Use brew uninstall --cask rather than deleting by hand."),

        // MARK: /private
        "/private/etc": .keep("System configuration files such as hosts and sudoers. Small but critical; edit only when you know the exact change."),
        "/private/tmp": .keep("Temporary files of running programs, cleared on restart. Restart instead of deleting, because running programs may still use them."),
        "/private/var": .keep("Variable system data: per-user temporary files, databases, logs, and swap. macOS manages it, and large size usually comes from the folders subfolder."),
        "/private/var/folders": .keep("Per-user temporary files and caches created by macOS and apps. Can grow very large after crashes or heavy app use. A restart clears part of it; do not delete by hand."),
        "/private/var/vm": .keep("Swap files and the sleep image. Size follows memory pressure and installed RAM, and swap shrinks after a restart."),
        "/private/var/vm/sleepimage": .keep("Copy of memory written to disk for sleep, about the size of installed RAM. macOS recreates it if removed."),
        "/private/var/db": .keep("System databases: system logs, Rosetta translations, permissions, and installer records. Deleting them can break core macOS features."),
        "/private/var/db/diagnostics": .keep("The macOS unified system log. macOS trims it automatically."),
        "/private/var/db/uuidtext": .keep("Lookup data the macOS unified system log needs to display messages. macOS trims it automatically."),
        "/private/var/db/oah": .keep("Rosetta's translated copies of Intel apps on Apple silicon. Rebuilt on demand, but managed by macOS."),
        "/private/var/log": .review("System and service log files, rotated by macOS. Usually small; useful for troubleshooting."),
        "/private/var/logs": .review("System and service log files. Usually small; useful for troubleshooting."),
        "/private/var/tmp": .keep("Temporary files that survive a restart. macOS and installers remove their own files over time."),
        "/private/var/root": .keep("The home folder of the system's root account. Its contents belong to macOS and system services."),
        "/private/var/MobileSoftwareUpdate": .keep("Working files for macOS updates. macOS removes them after the update."),
        "/private/var/protected": .keep("Protected system data for trust and security services. macOS manages it."),

        // MARK: /Library
        "/Library/Application Support": .review("Data for apps and drivers installed for all users. Often grows with audio content, security tools, and updaters. Leftovers of removed apps can be deleted."),
        "/Library/Apple": .keep("Software installed and managed by Apple outside the sealed system, such as Rosetta. macOS manages it."),
        "/Library/Audio": .review("Audio plug-ins and Apple Loops, mostly from GarageBand and Logic Pro. Sound libraries can reach tens of gigabytes and can be removed from those apps."),
        "/Library/Caches": .safe("Caches for system-wide apps and services. Rebuilt automatically when needed."),
        "/Library/Developer": .review("Apple developer tools installed for all users: Command Line Tools and simulator runtimes, which are several gigabytes each."),
        "/Library/Developer/CommandLineTools": .review("Compilers and Git for the terminal, used by Homebrew and many developer tools. Reinstall with xcode-select --install."),
        "/Library/Developer/CoreSimulator": .review("iOS, watchOS, and tvOS simulator runtimes, several gigabytes each. Remove them in Xcode under Settings > Components."),
        "/Library/Desktop Pictures": .review("Wallpapers added to this Mac. Built-in wallpapers live elsewhere and are not affected."),
        "/Library/Extensions": .keep("Third-party kernel drivers. Removing one disables its hardware or software; use the vendor's uninstaller."),
        "/Library/Fonts": .review("Fonts available to all users. Documents and apps that use a removed font will substitute another one."),
        "/Library/Frameworks": .keep("Shared code installed for all users, such as Python or audio drivers. Apps that depend on a framework stop working without it."),
        "/Library/Java": .review("Java runtimes installed for all users. Tools that depend on a removed version stop working."),
        "/Library/Keychains": .keep("System keychains with certificates and network passwords. Deleting them breaks secure connections and saved network access."),
        "/Library/LaunchAgents": .review("Programs started for every user at login, mostly app updaters and helpers. Removing a file stops that helper; review them in System Settings > General > Login Items."),
        "/Library/LaunchDaemons": .review("Background services started when the Mac boots, installed by third-party apps. Removing a file stops that service and may break its app."),
        "/Library/Logs": .safe("Logs from system-wide apps and services. Useful only for troubleshooting; apps create new ones."),
        "/Library/Preferences": .keep("System-wide settings for macOS and apps. Deleting them resets those settings, including network configuration."),
        "/Library/PrivilegedHelperTools": .review("Helpers that apps install to run with administrator rights. Leftovers of removed apps can go; others are needed by their apps."),
        "/Library/Printers": .review("Printer drivers and icons. Can be several gigabytes; macOS downloads drivers again when a printer is added."),
        "/Library/Python": .review("Packages for system Python installs. Scripts depending on them stop working."),
        "/Library/Receipts": .keep("Records of installed packages. Installers and macOS use them to track what is installed."),
        "/Library/Security": .keep("Security plug-ins and trust settings. Often part of device management or security software."),
        "/Library/SystemExtensions": .keep("Drivers and network or security extensions installed by apps. Remove them through their app or System Settings."),
        "/Library/Updates": .keep("macOS updates that were downloaded and are waiting to install. macOS removes them afterward."),
        "/Library/Application Support/GarageBand": .review("Sound libraries for GarageBand. They can reach tens of gigabytes and are downloaded again from within the app."),
        "/Library/Application Support/Logic": .review("Sound libraries for Logic Pro. They can reach tens of gigabytes and can be relocated or removed from within the app."),
        "/Library/Application Support/Apple": .keep("Support files for Apple software and services. macOS and Apple apps manage them."),
    ]

    /// Exact locations relative to a home folder.
    static let homePaths: [String: StorageItemDescription] = [
        // MARK: Standard folders
        "Applications": .review("Apps installed only for this user, including web apps. Uninstall by moving an app to the Trash."),
        "Desktop": .review("Files shown on the desktop. These are personal files, and if iCloud Desktop & Documents is on, deleting removes them from all devices."),
        "Documents": .review("Personal documents and data some apps store here. If iCloud Desktop & Documents is on, deleting removes them from all devices."),
        "Downloads": .review("Files saved from browsers and other apps. Often the easiest place to free space: old installers and archives can usually go."),
        "Library": .keep("Personal app data, settings, caches, and mail, hidden by default. Deleting it entirely resets apps; only some subfolders can be cleared safely."),
        "Movies": .review("Personal videos plus TV and iMovie libraries. A few large files usually account for its size."),
        "Music": .review("Music and GarageBand libraries, including downloaded tracks. Manage the content from within those apps."),
        "Pictures": .review("Personal images and the Photos library, which is usually the largest item. Manage photos from within Photos."),
        "Public": .review("Files shared with other users on this Mac and over file sharing. Personal files that may be intentionally shared."),
        "Sites": .review("A legacy folder for personal websites. Contains only what you placed there."),
        "Applications (Parallels)": .safe("Shortcuts to Windows apps in Parallels Desktop virtual machines. Small; Parallels recreates them."),
        "Parallels": .review("Parallels Desktop virtual machines. Each one is a full computer disk that can take tens of gigabytes; delete them from Parallels."),
        "Music/Music": .review("The Apple Music library: downloaded songs and their database. Remove downloads from the Music app rather than deleting files here."),
        "Music/iTunes": .review("A legacy iTunes library, possibly still holding media and old iOS backups. Check whether the Music app still uses it before deleting."),
        "Music/GarageBand": .review("Your GarageBand projects."),
        "Movies/TV": .review("The Apple TV app library with downloaded shows and movies. Remove downloads from the TV app."),
        "Dropbox": .review("Files synced with Dropbox. Deleting here deletes them in the cloud too. To free space, use online-only mode in Dropbox."),
        "Google Drive": .review("Files synced with Google Drive. Deleting here deletes them in the cloud too. To free space, use streaming mode in Google Drive."),
        "OneDrive": .review("Files synced with OneDrive. Deleting here deletes them in the cloud too. To free space, use Free Up Space in Finder."),
        "go": .review("The Go workspace: downloaded modules and installed programs. Clear modules with go clean -modcache; they download again on the next build."),
        "anaconda3": .review("The Anaconda Python distribution with its packages and environments. Size comes from data science libraries. Remove environments with conda rather than by hand."),
        "miniconda3": .review("The Miniconda Python distribution with its packages and environments. Remove environments with conda rather than by hand."),

        // MARK: Hidden folders
        ".Trash": .safe("Items moved to the Trash. They still use space until the Trash is emptied."),
        ".cache": .safe("Shared cache for command-line and AI tools. Everything can be recreated, but AI tools may keep large models here that must be downloaded again."),
        ".cache/huggingface": .safe("Models and datasets downloaded through Hugging Face libraries. They can be huge and download again when a program next needs them."),
        ".cache/lm-studio": .review("Data and models from LM Studio. Models can be many gigabytes each; remove them in LM Studio to avoid downloading them by accident."),
        ".cache/uv": .safe("Packages downloaded by the uv Python tool. Run uv cache clean; they download again as needed."),
        ".cache/pip": .safe("Packages downloaded by pip. They download again as needed."),
        ".cache/whisper": .safe("Speech recognition models for Whisper. They download again when needed."),
        ".cache/puppeteer": .safe("Browsers downloaded for Puppeteer automation. Reinstalled by npx puppeteer browsers install or by the next install."),
        ".config": .review("Settings for command-line tools, sometimes including login tokens. Usually small; deleting resets those tools."),
        ".local": .review("Per-user programs and app data following Linux conventions. May hold tools, runtimes, and models installed by CLIs."),
        ".local/bin": .review("Command-line programs installed for this user. Commands stop working when removed."),
        ".local/share": .review("Data for command-line tools, such as installed runtimes and databases. Check the tool's own subfolder before deleting."),
        ".local/state": .safe("Logs and history for command-line tools. Tools recreate it, though history is lost."),
        ".ssh": .keep("SSH keys and known hosts. Deleting private keys cuts off access to servers and Git hosts, and they often cannot be recovered."),
        ".gnupg": .keep("GPG keys for signing and encryption. Deleted private keys cannot be recovered without a backup."),
        ".aws": .keep("AWS CLI credentials and settings. Deleting signs tools out of AWS."),
        ".azure": .review("Azure CLI sign-in and cached data. Deleting signs tools out of Azure."),
        ".kube": .keep("Kubernetes cluster access configuration and caches. Deleting removes kubectl's access to clusters."),
        ".docker": .review("Docker CLI settings, sign-ins, and plug-ins. Images and containers are stored elsewhere, in Library/Containers/com.docker.docker."),
        ".minikube": .review("Local Kubernetes cluster and its cached images. Run minikube delete --all to remove it; the cluster is lost."),
        ".npm": .safe("npm's package download cache. Grows with every install. Run npm cache clean --force; packages download again as needed."),
        ".nvm": .review("Node.js versions installed with nvm. Each version takes hundreds of megabytes. Remove old ones with nvm uninstall."),
        ".bun": .review("The Bun runtime, global packages, and download cache. Clear the cache with bun pm cache rm."),
        ".yarn": .safe("Yarn's package cache. Packages download again on the next install."),
        ".pnpm-store": .safe("pnpm's shared package store. Run pnpm store prune to remove unused packages."),
        ".cargo": .review("Rust's package cache and installed programs. The registry subfolder downloads again; bin holds tools you installed."),
        ".rustup": .review("Rust compiler toolchains, about a gigabyte each. Remove old ones with rustup toolchain uninstall."),
        ".gradle": .safe("Gradle's dependency caches and wrapper downloads. They download again on the next build, which takes longer."),
        ".m2": .safe("Maven's settings and downloaded dependencies. The repository downloads again on the next build; keep settings.xml if customized."),
        ".sdkman": .review("Java and JVM tools installed with SDKMAN. Remove old versions with sdk uninstall."),
        ".android": .review("Android SDK settings and emulator images. Emulators can take many gigabytes each; remove them in Android Studio's Device Manager."),
        ".conda": .review("Conda environments and package data for this user. Remove environments with conda env remove."),
        ".pyenv": .review("Python versions installed with pyenv, a few hundred megabytes each. Remove old ones with pyenv uninstall."),
        ".rbenv": .review("Ruby versions installed with rbenv. Remove old ones with rbenv uninstall."),
        ".gem": .safe("Ruby gems installed for this user. Reinstall them with gem install or bundle install."),
        ".cocoapods": .safe("CocoaPods spec repositories and caches. They download again on the next pod install."),
        ".nuget": .safe("NuGet's .NET package cache. Packages download again on the next restore."),
        ".dotnet": .review(".NET tools and SDK data for this user. Global tools must be reinstalled."),
        ".swiftpm": .safe("Swift Package Manager caches and settings. Dependencies download again on the next build."),
        ".terraform.d": .review("Terraform plug-in cache and CLI settings. Plug-ins download again; a sign-in token here would be lost."),
        ".vagrant.d": .review("Vagrant base boxes, often several gigabytes each. Remove them with vagrant box remove."),
        ".keras": .safe("Keras models and datasets. They download again when a program next needs them."),
        ".ollama": .review("Models downloaded by Ollama, often several gigabytes each. Remove them with ollama rm; deleted models must be downloaded again."),
        ".lmstudio": .review("LM Studio models and data, often many gigabytes. Remove models from LM Studio; they must be downloaded again."),
        ".vscode": .review("Extensions installed in Visual Studio Code. Deleting removes them; settings stay in Library/Application Support/Code."),
        ".cursor": .review("Cursor's extensions, project data, and agent settings. Deleting removes extensions and resets settings stored here."),
        ".windsurf": .review("Windsurf's extensions and settings. Deleting removes extensions and resets settings stored here."),
        ".claude": .review("Claude Code settings, session history, and plug-ins. History can grow over time; deleting loses it and resets your configuration."),
        ".codex": .review("OpenAI Codex settings, session history, and sign-in. Deleting loses history and signs you out."),
        ".gemini": .review("Google Gemini CLI and Antigravity settings, sign-in, and agent history. Deleting signs you out and loses that history."),
        ".zsh_sessions": .safe("Saved Terminal session history. Small; Terminal creates it again."),
        ".bash_sessions": .safe("Saved Terminal session history from Bash. Small; safe to remove."),

        // MARK: Library
        "Library/Accounts": .keep("Internet accounts added in System Settings. Deleting signs you out of them."),
        "Library/Application Scripts": .keep("Scripts that sandboxed apps may run. Usually small and managed by those apps."),
        "Library/Application Support": .review("The main data store of apps: databases, profiles, downloaded content, and local AI models. Usually large, and removed apps leave data behind. Removing an app's folder resets it."),
        "Library/Assistant": .keep("Siri and dictation data. macOS manages it."),
        "Library/Autosave Information": .review("Unsaved document versions kept by apps. May hold your only copy of unsaved work."),
        "Library/Biome": .keep("On-device activity data that powers Siri and suggestions. macOS manages and trims it."),
        "Library/Caches": .safe("Temporary data apps can rebuild, such as downloads and thumbnails. Close apps first; some may start slower or download again."),
        "Library/Calendars": .review("Local calendar data, including synced events. Manage it from the Calendar app."),
        "Library/CloudStorage": .review("Files from Dropbox, Google Drive, OneDrive, and similar services. Deleting removes them from the cloud too; free space with the service's online-only option."),
        "Library/Containers": .review("Private storage of sandboxed apps: documents, settings, and caches. A single app can hold many gigabytes. Deleting a folder resets that app and can lose its data."),
        "Library/Containers/com.docker.docker": .review("Docker's virtual disk with all images, containers, and volumes. Free space with docker system prune; deleting by hand erases all of it."),
        "Library/Containers/com.apple.mail": .review("Apple Mail's sandbox data and settings. Manage mail from the Mail app."),
        "Library/Containers/com.apple.mediaanalysisd": .keep("On-device photo and video analysis data for search and suggestions. macOS manages it."),
        "Library/Containers/com.apple.geod": .keep("Cached map data for macOS location services. macOS manages it."),
        "Library/Cookies": .review("Website cookies for Safari and other apps. Deleting signs you out of sites."),
        "Library/Daemon Containers": .keep("Private storage for macOS background services. macOS manages it."),
        "Library/Developer": .review("Xcode's build data, simulators, and device support files. Often large on development Macs, and most of it can be rebuilt."),
        "Library/Developer/CoreSimulator": .review("Simulated iPhones and iPads with their apps and data. Run xcrun simctl delete unavailable to remove outdated devices."),
        "Library/Developer/CoreSimulator/Caches": .safe("Simulator caches rebuilt automatically when needed."),
        "Library/Developer/CoreSimulator/Devices": .review("Each simulated device with its installed apps and data. Run xcrun simctl delete unavailable to remove outdated ones."),
        "Library/Developer/Xcode": .review("Xcode's build products, archives, and device symbols. Most space comes from DerivedData and iOS DeviceSupport, both rebuilt when needed."),
        "Library/Developer/Xcode/Archives": .review("Builds of apps you archived. Keep those you may need to debug crash reports from released versions."),
        "Library/Developer/Xcode/DerivedData": .safe("Xcode's build products and indexes. Grows with every project. Xcode rebuilds it, so the next build takes longer."),
        "Library/Developer/Xcode/iOS DeviceSupport": .safe("Debug symbols for each iOS version you connected, a few gigabytes each. Xcode recreates them when a device is connected."),
        "Library/Fonts": .review("Fonts installed for this user. Documents and apps using a removed font will substitute another one."),
        "Library/Group Containers": .review("Data shared between apps from one vendor, such as Microsoft Office or Apple Notes. Deleting can lose app data."),
        "Library/Group Containers/UBF8T346G9.Office": .review("Data shared by Microsoft Office apps: settings, fonts, templates, and cached files. Deleting resets Office and can lose unsynced items."),
        "Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite": .review("OneDrive's settings and sync data. Deleting forces OneDrive to set up again."),
        "Library/HTTPStorages": .review("Web data such as cookies stored by apps. Rebuilt automatically, but some apps may sign you out."),
        "Library/HomeKit": .keep("Home app configuration. Managed by macOS and synced through iCloud."),
        "Library/IdentityServices": .keep("Sign-in data for Messages and FaceTime. Deleting can break those services."),
        "Library/IntelligencePlatform": .keep("On-device data for Apple Intelligence and personal context. macOS manages it."),
        "Library/Keychains": .keep("Your saved passwords, certificates, and keys. Deleting loses them for good unless they are in iCloud Keychain or a backup."),
        "Library/LanguageModeling": .keep("Learned typing predictions and corrections. Small and managed by macOS."),
        "Library/LaunchAgents": .review("Programs started at your login, mostly app updaters and helpers. Removing a file stops that helper; leftovers of removed apps can go."),
        "Library/Logs": .safe("Diagnostic logs from apps. Useful only for troubleshooting; apps create new ones."),
        "Library/Mail": .review("Apple Mail's local copy of messages and attachments. It grows with mailbox size. Manage it from Mail; deleting here can lose mail not stored on a server."),
        "Library/Maps": .review("Data of the Maps app. Usually small; manage it from Maps."),
        "Library/MediaAnalysis": .keep("On-device analysis of photos and videos for search. macOS manages it."),
        "Library/Messages": .review("Message history and every attachment received. Attachments are usually the large part. Delete conversations in Messages, not here."),
        "Library/Metadata": .keep("Spotlight data used for search, and app metadata. macOS manages and rebuilds it."),
        "Library/Mobile Documents": .review("iCloud Drive and app data synced with iCloud. Deleting removes items from all devices. To free space, use Remove Download in Finder."),
        "Library/News": .review("Data of the Apple News app. Usually small; manage it from News."),
        "Library/Passes": .review("Wallet cards and passes. Manage them from the Wallet app."),
        "Library/Photos": .keep("System data for the Photos app. The library itself is in the Pictures folder."),
        "Library/PersonalizationPortrait": .keep("On-device personalization data for suggestions. macOS manages it."),
        "Library/Preferences": .review("Settings files for apps and macOS. Small even with many apps. Deleting a file resets that app's settings."),
        "Library/Python": .review("Python packages installed with pip --user. Scripts depending on them stop working until they are reinstalled."),
        "Library/Reminders": .review("Local reminders data, including synced items. Manage it from the Reminders app."),
        "Library/Safari": .review("Safari bookmarks, history, and reading list data. Manage it from Safari; deleting loses data that is not synced."),
        "Library/Saved Application State": .safe("Window layouts macOS restores when apps reopen. Small; deleting only loses those positions."),
        "Library/ScreenRecordings": .review("Screen recordings saved by apps such as screenshot tools. These can be large and are not rebuilt."),
        "Library/Shortcuts": .review("Your Shortcuts automations. Usually synced with iCloud."),
        "Library/Sounds": .review("Custom alert sounds. Contains only what you added."),
        "Library/Spelling": .review("Your personal spelling dictionary."),
        "Library/Suggestions": .keep("On-device data for Siri suggestions. macOS manages it."),
        "Library/Translation": .safe("Language packs for Apple Translate. Remove them in System Settings or download them again when needed."),
        "Library/Trial": .keep("Feature assets Apple delivers to macOS services. macOS manages and cleans them."),
        "Library/UnifiedAssetFramework": .keep("On-device assets used by macOS features. macOS manages them."),
        "Library/WebKit": .review("Website data for apps using embedded web views. Rebuilt automatically, but apps may sign you out."),
        "Library/pnpm": .safe("pnpm's shared package store and global tools. Run pnpm store prune to remove unused packages."),

        // MARK: Library caches of common tools
        "Library/Caches/Homebrew": .safe("Installers downloaded by Homebrew. Clear with brew cleanup --prune=all; they download again when needed."),
        "Library/Caches/pip": .safe("Packages downloaded by pip. They download again as needed."),
        "Library/Caches/pnpm": .safe("pnpm's package metadata cache. It downloads again as needed."),
        "Library/Caches/Yarn": .safe("Yarn's package cache. Packages download again on the next install."),
        "Library/Caches/CocoaPods": .safe("CocoaPods' download cache. Pods download again on the next install."),
        "Library/Caches/ms-playwright": .safe("Browsers downloaded for Playwright testing. Restore them with npx playwright install."),
        "Library/Caches/Cypress": .safe("Cypress test runner binaries. Restore them with npx cypress install."),
        "Library/Caches/JetBrains": .safe("Indexes and caches of JetBrains IDEs. Rebuilt when a project is opened, which takes a while."),

        // MARK: Application data of common apps
        "Library/Application Support/AddressBook": .review("Your contacts database and images. Manage it from the Contacts app."),
        "Library/Application Support/Adobe": .review("Settings, plug-ins, and shared content for Adobe apps. Use Creative Cloud to remove apps rather than deleting here."),
        "Library/Application Support/Arc": .review("Arc browser profiles, including history, extensions, and site data. Mostly grows through site data. Deleting a profile loses data that is not synced."),
        "Library/Application Support/BraveSoftware": .review("Brave browser profiles, including history, extensions, and site data. Deleting loses data that is not synced."),
        "Library/Application Support/Caches": .safe("Cache data placed here by apps. Rebuilt automatically when needed."),
        "Library/Application Support/CallHistoryDB": .keep("FaceTime and phone call history. macOS manages it."),
        "Library/Application Support/Claude": .review("Data of the Claude desktop app: settings, local state, and downloaded components. Deleting signs you out and downloads components again."),
        "Library/Application Support/CloudDocs": .keep("Internal sync database for iCloud Drive. Deleting can disrupt syncing."),
        "Library/Application Support/Code": .review("Visual Studio Code settings, workspace state, and extension data, often grown by caches and logs. Deleting resets the editor."),
        "Library/Application Support/Cursor": .review("Cursor settings, workspace state, and AI chat history. History and caches can grow to many gigabytes. Deleting resets the editor and loses history."),
        "Library/Application Support/Docker Desktop": .review("Docker Desktop's app state. Images and volumes are stored elsewhere, in Library/Containers/com.docker.docker."),
        "Library/Application Support/Dropbox": .review("Dropbox app data and sync state, not your files. Deleting may force a re-sync."),
        "Library/Application Support/Figma": .safe("Figma's cached files and settings. Your designs live in the cloud and download again."),
        "Library/Application Support/Firefox": .review("Firefox profiles with bookmarks, passwords, extensions, and site data. Deleting loses data that is not synced."),
        "Library/Application Support/Google": .review("Data of Google apps, mainly Chrome profiles with history, extensions, passwords, and site data. Deleting loses data not synced to your account."),
        "Library/Application Support/Google/Chrome": .review("Chrome profiles with history, extensions, passwords, and site data; on-device AI models can add gigabytes. Deleting loses data not synced to your account."),
        "Library/Application Support/JetBrains": .review("Plug-ins and settings of JetBrains IDEs, including old versions. Folders of IDE versions you no longer use can be removed."),
        "Library/Application Support/Knowledge": .keep("On-device app usage history that powers suggestions and Screen Time. macOS manages it."),
        "Library/Application Support/LM Studio": .review("LM Studio settings and conversations. Downloaded models may be stored here or in its models folder; remove them in the app."),
        "Library/Application Support/Microsoft": .review("Data of Microsoft apps such as Teams, Office, and AutoUpdate. Deleting resets those apps and may lose offline data."),
        "Library/Application Support/Microsoft Edge": .review("Edge browser profiles with history, extensions, passwords, and site data. Deleting loses data not synced to your account."),
        "Library/Application Support/MobileSync": .review("iPhone and iPad backups made on this Mac, often tens of gigabytes. Delete old ones in Finder under the device's Manage Backups."),
        "Library/Application Support/MobileSync/Backup": .review("iPhone and iPad backups made on this Mac, often tens of gigabytes. Delete old ones in Finder under the device's Manage Backups."),
        "Library/Application Support/Notion": .review("Notion's cached pages and settings. Content lives in the cloud and downloads again, except edits not yet synced."),
        "Library/Application Support/Ollama": .review("Ollama app state. Downloaded models are usually in .ollama in your home folder."),
        "Library/Application Support/Postman": .review("Postman's local data and settings. Unsynced collections can be lost, so export them first."),
        "Library/Application Support/Slack": .safe("Slack's caches, downloads, and sign-in state. Content returns from Slack's servers after signing in again."),
        "Library/Application Support/Spotify": .safe("Spotify's settings and data. Offline music downloads again."),
        "Library/Application Support/Steam": .review("Steam and its installed games, which can take many gigabytes each. Uninstall games from Steam."),
        "Library/Application Support/Windsurf": .review("Windsurf settings, workspace state, and AI chat history. Deleting resets the editor and loses history."),
        "Library/Application Support/Xcode": .review("Xcode's settings and support data. Deleting resets parts of Xcode's configuration."),
        "Library/Application Support/com.apple.TCC": .keep("The privacy permission database for camera, microphone, and file access. Deleting resets granted permissions."),
        "Library/Application Support/discord": .safe("Discord's caches and sign-in state. Content returns from Discord's servers after signing in again."),
        "Library/Application Support/iCloud": .keep("iCloud account data. macOS manages it."),
        "Library/Application Support/zoom.us": .review("Zoom's settings, background assets, and data. Recordings are stored in Documents/Zoom by default."),
    ]

    /// Any direct child of these folders under a home folder.
    static let homeChildren: [String: StorageItemDescription] = [
        "Library/Application Support": .review("Data for one app, such as databases, profiles, and downloaded content. If the app is uninstalled, this can go. Otherwise deleting resets it and may lose local data."),
        "Library/Caches": .safe("Temporary data for one app. Close the app first; it is rebuilt or downloaded again when needed."),
        "Library/CloudStorage": .review("Files synced by one cloud service. Deleting removes them from the cloud too; free space with the service's online-only option."),
        "Library/Containers": .review("Private storage for one sandboxed app, with its documents, settings, and caches. If the app is uninstalled, this can go. Otherwise deleting resets it."),
        "Library/Group Containers": .review("Data shared between apps from one vendor. If those apps are uninstalled, this can go. Otherwise deleting can lose app data."),
        "Library/HTTPStorages": .review("Web data such as cookies for one app. Rebuilt automatically, though the app may sign you out."),
        "Library/Logs": .safe("Diagnostic logs from one app. Useful only for troubleshooting; the app creates new ones."),
        "Library/Mobile Documents": .review("An iCloud folder for one app. Deleting removes it from all devices using that iCloud account."),
        "Library/Saved Application State": .safe("Window layout macOS restores when this app reopens. Deleting only loses those positions."),
        "Library/WebKit": .review("Website data for one app. Rebuilt automatically, though the app may sign you out."),
        "Library/Developer/CoreSimulator/Devices": .review("One simulated device with its installed apps and data. Run xcrun simctl delete unavailable to remove outdated ones."),
        "Library/Developer/Xcode/DerivedData": .safe("Xcode's build products and index for one project. Xcode rebuilds it on the next build."),
        "Library/Developer/Xcode/iOS DeviceSupport": .safe("Debug symbols for one iOS version. Xcode recreates them when a device with that version is connected."),
        ".cache": .safe("Cached data for one tool. The tool recreates or downloads it again when needed."),
    ]

    /// Any direct child of these absolute folders.
    static let absoluteChildren: [String: StorageItemDescription] = [
        "/Volumes": .review("A mounted disk, disk image, or network share. Its size is on that disk, not on the startup disk. Eject it from Finder when finished."),
        "/Library/Application Support": .review("Data for one app or driver installed for all users. If the app is uninstalled, this can go. Otherwise deleting can break it."),
        "/Library/Caches": .safe("Temporary data for one system-wide app or service. Rebuilt when needed."),
        "/Library/Logs": .safe("Diagnostic logs from one system-wide app or service. Useful only for troubleshooting."),
        "/opt/homebrew/Cellar": .review("One Homebrew formula with its installed versions. Remove with brew uninstall so that Homebrew stays consistent."),
        "/opt/homebrew/Caskroom": .review("Records of an app installed with Homebrew Cask. Remove with brew uninstall --cask."),
        "/usr/local/Cellar": .review("One Homebrew formula with its installed versions. Remove with brew uninstall so that Homebrew stays consistent."),
        "/usr/local/Caskroom": .review("Records of an app installed with Homebrew Cask. Remove with brew uninstall --cask."),
    ]

    /// Folder names with one meaning wherever they appear.
    static let directoryNames: [String: StorageItemDescription] = [
        "node_modules": .safe("JavaScript packages for this project, often very large because each project keeps its own copy. Reinstall with npm, pnpm, or yarn install."),
        ".git": .keep("This project's entire Git history. Deleting loses all local commits and branches. Run git gc to compact it."),
        "__pycache__": .safe("Compiled Python files. Python recreates them on the next run."),
        ".venv": .safe("This project's Python virtual environment with its installed packages. Recreate it from the project's requirements."),
        ".next": .safe("Next.js build output and cache. Recreated by the next build or dev run."),
        ".nuxt": .safe("Nuxt build output. Recreated by the next build or dev run."),
        ".svelte-kit": .safe("SvelteKit build output. Recreated by the next build or dev run."),
        ".angular": .safe("Angular build cache. Recreated by the next build."),
        ".turbo": .safe("Turborepo task cache. Recreated by the next build, which takes longer."),
        ".parcel-cache": .safe("Parcel build cache. Recreated by the next build."),
        ".pytest_cache": .safe("pytest's test run cache. Recreated by the next run."),
        ".mypy_cache": .safe("mypy's type-checking cache. Recreated by the next run."),
        ".ruff_cache": .safe("Ruff's lint cache. Recreated by the next run."),
        ".tox": .safe("tox test environments. Recreated by the next run."),
        ".ipynb_checkpoints": .review("Jupyter's automatic notebook checkpoints. They hold older versions of your notebooks."),
        ".terraform": .safe("Terraform's downloaded providers and modules for this project. Restore them with terraform init."),
        ".gradle": .safe("Gradle's build cache for this project. Recreated by the next build."),
        ".dart_tool": .safe("Dart and Flutter tool data for this project. Recreated by the next pub get or build."),
        ".build": .safe("Swift Package Manager build products for this project. Recreated by the next build."),
        "DerivedData": .safe("Xcode build products and indexes. Xcode rebuilds them, so the next build takes longer."),
        ".Trashes": .safe("Items moved to the Trash from this disk. They still use space until the Trash is emptied."),
        ".Spotlight-V100": .keep("This disk's Spotlight search index. macOS maintains it."),
        ".fseventsd": .keep("This disk's log of file changes, used by backups and sync. macOS maintains it."),
        ".DocumentRevisions-V100": .keep("Saved document versions for this disk. Deleting loses the Version History of documents."),
        ".TemporaryItems": .keep("Temporary files apps create on this disk. macOS removes them."),
        "Backups.backupdb": .keep("Time Machine backups. Manage them from Time Machine; deleting by hand can damage the backup."),
    ]

    /// File names with one meaning wherever they appear.
    static let fileNames: [String: StorageItemDescription] = [
        ".DS_Store": .safe("Finder's view settings for this folder. Very small; Finder recreates it."),
        "sleepimage": .keep("Copy of memory written to disk for sleep, about the size of installed RAM. macOS recreates it if removed."),
    ]

    /// Folder packages that macOS treats as a single item.
    static let directoryExtensions: [String: StorageItemDescription] = [
        "photoslibrary": .review("A Photos library holding originals, edits, and thumbnails. Manage it from Photos; use Optimize Mac Storage to free space when using iCloud."),
        "musiclibrary": .review("An Apple Music library database. Manage it from the Music app."),
        "tvlibrary": .review("An Apple TV app library database. Manage it from the TV app."),
        "imovielibrary": .review("An iMovie library with media and render files. Delete projects or render files from iMovie."),
        "fcpbundle": .review("A Final Cut Pro library with media and render files. Delete generated files from Final Cut Pro."),
        "logicx": .review("A Logic Pro project with its audio files."),
        "band": .review("A GarageBand project with its audio files."),
        "xcarchive": .review("An archived app build from Xcode. Keep those you may need to debug crash reports from released versions."),
        "pvm": .review("A Parallels virtual machine with a full computer disk. Delete it from Parallels."),
        "utm": .review("A UTM virtual machine with a full computer disk. Delete it from UTM."),
        "vmwarevm": .review("A VMware virtual machine with a full computer disk. Delete it from VMware."),
        "sparsebundle": .review("A disk image that grows with its contents, possibly a backup. Mount it to check what it holds."),
    ]

    /// Single files whose type explains what they are.
    static let fileExtensions: [String: StorageItemDescription] = [
        "dmg": .review("A disk image, usually an app installer that is no longer needed once the app is installed. It can also hold personal files, so check it first."),
        "pkg": .safe("An installer package. Once the software is installed it is no longer needed."),
        "iso": .review("A disk image, often an operating system installer. Check whether a virtual machine still uses it."),
        "ipsw": .safe("An iPhone or iPad system image downloaded for restoring. Finder downloads it again when needed."),
        "xip": .safe("A compressed Apple installer archive, often for Xcode. Once it is extracted it is no longer needed."),
    ]

    /// Fallbacks for everything below a location not otherwise described.
    static let subtrees: [(prefix: String, description: StorageItemDescription)] = [
        ("/usr/local/", .review("Software you or an installer added outside macOS. Removing it uninstalls that tool.")),
        ("/private/var/folders/", .keep("Temporary files and caches created by macOS and apps for each user. A restart clears part of it; do not delete by hand.")),
        ("/System/", protectedSystemItem),
        ("/usr/", protectedSystemItem),
        ("/bin/", protectedSystemItem),
        ("/sbin/", protectedSystemItem),
    ]

    private static let protectedSystemItem = StorageItemDescription.keep(
        "Part of macOS, on the protected system volume. It is replaced by system updates and cannot be changed."
    )

    /// Every description, for checks that apply to the whole catalog.
    static var all: [StorageItemDescription] {
        [homeFolder, application, builtInApplication]
            + Array(absolutePaths.values)
            + Array(homePaths.values)
            + Array(homeChildren.values)
            + Array(absoluteChildren.values)
            + Array(directoryNames.values)
            + Array(fileNames.values)
            + Array(directoryExtensions.values)
            + Array(fileExtensions.values)
            + subtrees.map(\.description)
    }
}
