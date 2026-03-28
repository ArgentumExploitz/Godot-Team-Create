#!/bin/bash
echo "Building Headless Server for Godot Team Create..."

GODOT_BIN=${GODOT_BIN:-godot}

if ! command -v $GODOT_BIN &> /dev/null
then
    echo "Godot engine could not be found ($GODOT_BIN)."
else
    mkdir -p server_builds/linux server_builds/windows

    echo "Exporting Linux/X11 build..."
    $GODOT_BIN --headless --export-release "Linux/X11" server_builds/linux/TeamCreateServer.x86_64

    echo "Exporting Windows Desktop build..."
    $GODOT_BIN --headless --export-release "Windows Desktop" server_builds/windows/TeamCreateServer.exe

    echo "Builds completed! Check the 'server_builds' folder."
fi
