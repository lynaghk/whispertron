#!/bin/sh


cd "$(dirname "$0")"

mkdir -p mt/models/
FILE_PATH=mt/models/ggml-base.en.bin

if [ -f "$FILE_PATH" ]; then
    echo "File already exists. Skipping download."
else
    wget -O "$FILE_PATH" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin?download=true"
fi
