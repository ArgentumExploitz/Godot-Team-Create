# Commands List 💻

You can type these commands into the in-editor **Team Chat** (if you're host/admin) or directly into the **Dedicated Server Console**!

---

## 💬 Chat & Moderation Commands

| Command | What it does |
| :--- | :--- |
| `/chatimgs <true/false>` | Turn chat image sharing ON or OFF *(default: false)*. |
| `/lockchat <true/false>` | Lock the chat so only admins can send messages. |
| `/clearchat` | Wipes the chat history for everyone. |
| `/mute <user>` | Shuts a user up in chat. |
| `/unmute <user>` | Lets a muted user chat again. |
| `/admin <user>` | Gives admin superpowers to a user. |
| `/unadmin <user>` | Takes away admin superpowers. |
| `/kick <user>` | Kicks someone out of the session. |

---

## 📢 Server & Announcement Commands

| Command | What it does |
| :--- | :--- |
| `/msg <message>` | Broadcasts a server announcement message to everyone. |
| `/popup <message>` | Makes an in-your-face popup dialog appear on everyone's screen. |
| `/list` | Shows a list of all currently connected users. |
| `/info` | Displays server CPU, RAM usage, and active session stats. |
| `/togglejoins <true/false>` | Closes or opens the server to new players joining. |

---

## ⚙️ Server Management & Backup Commands

| Command | What it does |
| :--- | :--- |
| `/port <number>` | Changes the server listening port (default is `25567`). |
| `/backup [scene]` | Instantly saves a backup snapshot of your scenes. |
| `/autobackup <true/false>` | Toggles automatic scene backups. |
| `/filesize <bytes or none>` | Sets maximum file size allowed for asset uploads. |
| `/filetimeout <seconds>` | Sets file transfer timeout (default: 30s). |
| `/restart` | Restarts the server. |
| `/stop` | Cleanly saves all scenes and shuts down the server. |
