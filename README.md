
# $${ \textsf{\color{blue}Godot} \ \textsf{\color{green}Team} \ \textsf{\color{red}Create}}$$  

<p align="center">
<img width="541" height="423" alt="godoteam" src="https://github.com/user-attachments/assets/c8948365-a274-429e-ab95-fb524476dfa1" />
</p>

> [!WARNING]
> This plugin is super early and highly unstable. It will probably crash and might even corrupt/wipe your scene files. Seriously, do not use this for your actual project yet!

Basically, this is a Godot 4.* plugin that lets you and your friends jump into the same editor and build the game together in real-time. 

## What it actually does
- Connect up over LAN or straight through WebRTC.
- Automatically syncs project files and scenes so everyone is looking at the exact same stuff.
- Fair warning: as a side effect of how the sync works, some temporary files instantly become real assets now. 
- Tells you right in the editor when I push an update to the GitHub repo so you aren't running an ancient version.
- WIP user visuals: right now you can just see a selection box where your friends are clicking. Later on, I'm planning to add floating orbs with usernames for 3D scenes and actual cursors for 2D.

## What you need
- Godot 4.0 or newer.
- A decent internet connection between everyone.
- OPTIONAL: Hosted server, LAN and WebRTC might not work for some!

## How to get it running
1. Download the latest release.
2. Chuck the files into your project's `addons/` folder.
3. Open Godot, go to Project Settings -> Plugins.
4. Check the box to turn it on and hope for the best.

## Wanna help?
Since this thing is barely holding together right now, any testing is a massive help.
- **Breaking things:** If you find a bug (and you definitely will), open an issue up top and let me know exactly how you broke it so I can try to fix it.
- **Fixing things:** If you actually want to write some code and help out, pull requests are awesome. Just open a discussion first so we can chat before you spend hours coding some massive new feature.

## How to connect
### LAN Connection
**Host:**
1. Open the Team Create dock.
2. Click **Host**. This will start a server on your local machine (default port 12345).
3. Give your local IP address to your friends on the same network.

**User (Join):**
1. Open the Team Create dock.
2. Enter the Host's local IP address in the text box.
3. Click **Join**.

### WebRTC Connection
WebRTC allows you to connect over the internet without port forwarding by copying and pasting a connection string (Offer/Answer and ICE candidates).

**Host:**
1. Open the Team Create dock.
2. Click **WebRTC Host**.
3. The plugin will generate a connection string containing your Offer and ICE candidates.
4. Copy this connection string and send it to your friend.
5. Wait for your friend to send back their Answer connection string.
6. Paste their Answer connection string into the text box and click **Confirm**.

**User (Join):**
1. Open the Team Create dock.
2. Click **WebRTC Join**.
3. Paste the Host's Offer connection string into the text box and click **Confirm**.
4. The plugin will process the Offer and automatically generate your Answer connection string.
5. Copy your Answer connection string and send it back to the Host.
