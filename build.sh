#!/bin/sh

set -e

cd "$(dirname "$0")"

mkdir -p whispertron/models/
FILE_PATH=whispertron/models/ggml-base.en.bin

if [ -f "$FILE_PATH" ]; then
    echo "Whisper model already downloaded."
else
    wget -O "$FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true"
fi


xcodebuild -project whispertron.xcodeproj -scheme whispertron -configuration Release build ARCHS=arm64

echo "try running:\n"
echo "    open ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app"
echo "or"
echo "    cp -rf ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app /Applications/"
