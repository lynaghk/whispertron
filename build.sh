#!/bin/sh

set -e

cd "$(dirname "$0")"

mkdir -p whispertron/models/
#MODEL="ggml-base.en"
#MODEL="ggml-large-v3-turbo-q5_0"
MODEL="ggml-small.en-q5_1"
FILE_PATH="whispertron/models/model.bin"

if [ -f "$FILE_PATH" ]; then
    echo "Whisper model already downloaded."
else
    wget -O "$FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL.bin?download=true"
fi


xcodebuild -project whispertron.xcodeproj -scheme whispertron -configuration Release build ARCHS=arm64

echo "try running:\n"
echo "    open ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app"
echo "or"
echo "    cp -rf ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app /Applications/"
