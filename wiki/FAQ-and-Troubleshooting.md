# FAQ & Troubleshooting ❓

Here are answers to the most common questions and fixes for when things act up.

---

### Q: My friend can't connect to my game! What do I do?
1. **Check Windows Firewall:** When you host, Windows usually asks "Allow Godot to communicate on private/public networks?". If you clicked Cancel, Windows blocked it! Go to Windows Defender Firewall -> "Allow an app through firewall" and check Godot.
2. **Double check IP address:** Make sure you gave your friend your local IPv4 address (if on LAN) or your Radmin/Hamachi IP (if using VPN).
3. **Use Radmin VPN or Hamachi:** If you haven't forwarded port 25567 on your router, connecting over standard internet will fail. Just use Radmin VPN or Hamachi—it avoids router issues entirely.

---

### Q: Is using Hamachi or Radmin VPN legal?
**Yes, 100% legal.** They are standard, legitimate networking software made specifically for playing games and connecting with friends over virtual LANs. People have been using them for Minecraft, Godot, and retro games for over a decade.

---

### Q: What Godot versions are supported?
- You need **Godot 4.4 or newer** (Godot 4.4, 4.5, 4.6, 4.7, etc.).
- Godot 4.2 and older are **NOT** supported because they lack essential engine features (like `scene_saved` and modern resource IDs).
- It's strongly recommended that everyone on your team uses the same Godot version.

---

### Q: Something looks desynced or a node didn't update!
Just close the scene tab and reopen it, or click Disconnect and Join back in. The plugin will fetch the latest scene state cleanly.

---

### Q: Can this corrupt or mess up my scene files?
**Always keep a backup of your project!** We work hard to make everything rock solid, but game engines are complicated and bugs can happen. Keep backups or use Git so you can undo anything if a bug occurs.

---

### Q: I found a bug! Where do I report it?
Head over to the [GitHub Issues](https://github.com/N3rmis/Godot-Team-Create/issues) tab and open an issue! Tell me what you did right before the bug happened so I can reproduce it and fix it.
