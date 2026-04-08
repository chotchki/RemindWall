#!/bin/sh

#  ci_post_clone.sh
#  RemindWall
#
#  Created by Christopher Hotchkiss on 1/7/24.
#  As per: https://stackoverflow.com/a/77312559/160208

defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES

# Write the short git commit hash into Info.plist files
GIT_HASH=$(git -C "$CI_PRIMARY_REPOSITORY_PATH" rev-parse --short HEAD 2>/dev/null || echo "")
if [ -n "$GIT_HASH" ]; then
    /usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_HASH" "$CI_PRIMARY_REPOSITORY_PATH/RemindWall/Info.plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Set :GitCommitHash $GIT_HASH" "$CI_PRIMARY_REPOSITORY_PATH/RemindWalliOS/Info.plist" 2>/dev/null || true
fi
