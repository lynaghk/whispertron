My own lil' dictation app. For details see: [Making a dictation app in a weekend](https://kevinlynagh.com/newsletter/2024_10_transcription_app_art_wall/).

Works on my:

- M1 MacBook Air running MacOS 14.7.5 with XCode 16.1.
- M4 Mac Mini running MacOS 15.1.1 with XCode 16.2.

Run:

    ./build.sh

Then:

- copy the app to your `/Applications/` folder
- give it accessibility permissions
- run it

Hold down Control-Shift-H, say something, release Control-Shift-H, watch text appear.

I'm open to pairing or PRs that:

- add a single preferences window that allows you to configure the global activation hotkey
- make it easier for other people to build (is it possible without XCode?)
- graphically select and download Whisper models besides the base English one
- implement live transcription with a prinicpled approah like [Whisper Streaming](https://github.com/ufal/whisper_streaming/) (I assume it's good based on the video demos, but couldn't run it myself because, lol, [Python dependencies](https://github.com/ufal/whisper_streaming/issues/129))
- add a simple CLI that makes it easy to, e.g., get rough transcription of long, unchaptered YouTube videos so you can jump to parts.
- Don't add a leading space when writing into Emacs
- Optionally use larger model

I'm not interested in PRs related to:

- other operating systems or MacOS versions (I don't use them!)
- Best Practices. The only continuous integration I'm doing is using the app myself =D


Shout out to:

- [ggerganov/whisper.cpp: Port of OpenAI's Whisper model in C/C++](https://github.com/ggerganov/whisper.cpp)
- Espanso for figuring out how to [inject text in any app](https://github.com/espanso/espanso/blob/6b380d1edd94dff6505d97039ccb59c00ae1c5f4/espanso-inject/src/mac/native.mm#L30)

Have a great day!


# log

## 2025 Jun 12 - stylistic changes

Nikita contacted me with some nice stylistic changes that he vibe-coded with Claude, which I've merged in.

## 2025 May 3 - updated to latest Whisper.cpp

This should be faster than the previous version, since now Whisper.cpp uses Metal on MacOS.
It feels a bit snappier on my M1 Air, so I'm happy.

## 2024 oct 12 - mac text insertion

    func insertStringAtCursor(_ string: String) {
        let systemWideElement = AXUIElementCreateSystemWide()
        
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if result != .success {
            logger.error("Error getting focused element: \(result.rawValue)")
            return
        }

        let element = focusedElement as! AXUIElement

        var value: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)

        if let currentValue = value as? String {
            let newValue = currentValue + string
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, newValue as CFTypeRef)
        } else {
            AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, string as CFTypeRef)
        }
    }


trying to use the accessibility API like this doesn't work for Cursor or other apps that have custom text input thingies.
I think I might need to just generate keypress events?

ahh, found something that worked in https://github.com/espanso/espanso/blob/6b380d1edd94dff6505d97039ccb59c00ae1c5f4/espanso-inject/src/mac/native.mm#L30

## whisper streaming
https://github.com/ufal/whisper_streaming


wasn't able to run faster-whisper backend because 

    ValueError: This CTranslate2 package was not compiled with CUDA support

uv add whisper-timestamped

uv run whisper_online_server.py --model base.en --backend whisper_timestamped

ffmpeg -hide_banner -f avfoundation -list_devices true -i ""
ffmpeg -hide_banner -f avfoundation -i ":1" -ac 1 -ar 16000 -f s16le -loglevel error - | nc localhost 43007

unfortunately I kept running into this error after connecting and speaking for a few seconds.
Maybe the backend is busted somehow?
I'm able to capture data via ffmpeg from my mic, so that's not it.

  File "/Users/dev/software/whisper_streaming/.venv/lib/python3.9/site-packages/torch/nn/modules/module.py", line 1616, in _call_impl
    hook_result = hook(self, args, result)
  File "/Users/dev/software/whisper_streaming/.venv/lib/python3.9/site-packages/whisper_timestamped/transcribe.py", line 882, in <lambda>
    lambda layer, ins, outs, index=j: hook_attention_weights(layer, ins, outs, index))
  File "/Users/dev/software/whisper_streaming/.venv/lib/python3.9/site-packages/whisper_timestamped/transcribe.py", line 777, in hook_attention_weights
    if w.shape[-2] > 1:
AttributeError: 'NoneType' object has no attribute 'shape'


## whisper.cpp

bash ./models/download-ggml-model.sh base.en

brew install sdl
make stream
./stream -m ./models/ggml-base.en.bin -t 8 --step 500 --length 5000

