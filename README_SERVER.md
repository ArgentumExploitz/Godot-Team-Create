# Team Create Headless Server

To run the standalone server without the Godot editor UI, you can use Godot's headless mode, or use the pre-configured export presets to build standalone executables for Windows and Linux.

## Exporting Standalone Executables
You can easily export the server project as a standalone executable.

### Automated script (if you have godot in your PATH)
Run the `build_server.sh` script to automatically generate builds for Linux and Windows:
```sh
./build_server.sh
```
Builds will be saved in the `server_builds/` directory.

### Manual Export via Godot Editor
1. Open the project in Godot.
2. Go to **Project** -> **Export...**
3. Choose the target platform (**Windows Desktop** or **Linux/X11**).
4. For Windows, check **Export Console Wrapper** if you want to see the server console output.
5. Click **Export Project** and save it.

## Running the Server
Simply run the exported executable (`TeamCreateServer.exe` on Windows or `TeamCreateServer.x86_64` on Linux).
The server will automatically start and host on port `12345`.

You can also run it via Godot Engine without exporting:
```sh
godot --headless res://server/server.tscn
```
