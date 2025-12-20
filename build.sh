#!/bin/sh

set -e

cd "$(dirname "$0")"

mkdir -p whispertron/models/
#MODEL="ggml-base.en"
#MODEL="ggml-large-v3-turbo-q5_0"
MODEL="ggml-small.en-q5_1"
ENCODER="ggml-small.en-encoder"



MODEL_FILE_PATH="whispertron/models/model.bin"
if [ -f "$MODEL_FILE_PATH" ]; then
    echo "Whisper model already downloaded."
else
    echo "Downloading Whisper model."
    curl -L -o "$MODEL_FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL.bin?download=true"
fi


ENCODER_FILE_PATH="whispertron/models/model-encoder.mlmodelc"
if [ -d "$ENCODER_FILE_PATH" ]; then
    echo "Whisper encoder model already downloaded."
else
    echo "Downloading Whisper encoder model."
    curl -L -o "$ENCODER_FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ENCODER.mlmodelc.zip?download=true"
fi


FRAMEWORK_FILE="whisper-v1.8.2-xcframework.zip"
if [ -f "$FRAMEWORK_FILE" ]; then
    echo "Whisper framework already downloaded."
else
    echo "Downloading Whisper xcframework."
    curl -L -o "$FRAMEWORK_FILE" "https://github.com/ggml-org/whisper.cpp/releases/download/v1.8.2/whisper-v1.8.2-xcframework.zip"
    rm -rf whisper_xcframework
    unzip -d whisper_xcframework "$FRAMEWORK_FILE"
fi

xcodebuild -project whispertron.xcodeproj -scheme whispertron -configuration Release build ARCHS=arm64

echo "you'll probably need to reset accessibility permissions before the build will work:"
echo ""
echo "    tccutil reset Accessibility com.keminglabs.whispertron"
echo ""
echo "then try running:"
echo ""
echo "    open ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app"
echo ""
echo "or copy to your app folder for usage:"
echo ""
echo "    ditto ~/Library/Developer/Xcode/DerivedData/whispertron-*/Build/Products/Release/whispertron.app /Applications/whispertron.app"




