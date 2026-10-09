# Trigger Rally - D port

A port of Trigger Rally (originally C++/SDL2/OpenGL) to the D programming
language. The port uses the garbage collector freely and does not manage memory
by hand; GPU/audio handles are released explicitly with `unload()`/`release()`.

## Build and run

    cd d && dub build -b release     # produces ../bin/trigger-rally-d
    cd ../bin && ./trigger-rally-d

Requirements: a D compiler (dmd or ldc2), dub, and the SDL2, OpenGL and OpenAL
shared libraries (loaded at run time with `dlopen`).

PhysFS, tinyxml2, SDL_image, GLEW and ALUT are replaced by D modules
(`pengine/pvfs.d`, `xml.d`, `image.d`, `bindings/`). JPEG decoding uses the
`arsd-official:jpeg` dub package.

The game data lives in `data/`; the user config and player profiles are stored in
`~/.local/share/trigger-rally-team/trigger-rally/`.
