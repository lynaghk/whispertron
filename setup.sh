#!/bin/sh


cd "$(dirname "$0")"

mkdir -p mt/models/
FILE_PATH=mt/models/ggml-base.en.bin

if [ -f "$FILE_PATH" ]; then
    echo "Whisper model already downloaded."
else
    wget -O "$FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true"
fi


xcodebuild -project mt.xcodeproj -scheme mt -configuration Release build ARCHS=arm64

echo "try running:\n"
echo "open ~/Library/Developer/Xcode/DerivedData/mt-*/Build/Products/Release/mt.app"
