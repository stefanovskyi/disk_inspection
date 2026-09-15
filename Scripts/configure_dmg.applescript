on run arguments
    if (count of arguments) is not 2 then error "Expected the disk image name and mounted path"

    set volumeName to item 1 of arguments
    set mountPath to item 2 of arguments
    set backgroundFile to POSIX file (mountPath & "/.background/SpaceLensDMGBackground.tiff") as alias

    tell application "Finder"
        tell disk volumeName
            open

            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set bounds of container window to {200, 120, 920, 656}

            set viewOptions to icon view options of container window
            set arrangement of viewOptions to not arranged
            set icon size of viewOptions to 128
            set text size of viewOptions to 14
            set label position of viewOptions to bottom
            set background picture of viewOptions to backgroundFile

            set position of item "SpaceLens.app" of container window to {190, 165}
            set position of item "Applications" of container window to {530, 165}

            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
