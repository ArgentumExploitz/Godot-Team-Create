# FAQ & Troubleshooting

Some common problems and how to fix them.

### My friend can't connect
- **Check Windows Firewall:** Windows Firewall usually blocks incoming Godot connections by default. Open Windows Defender Firewall, click "Allow an app through firewall", find Godot, and check both Private and Public boxes.
- **Wrong IP:** Make sure you gave them your local IPv4 address (for LAN) or Radmin/Hamachi IP (for VPN), not a random gateway IP.
- **Port not open:** If you're trying to play over normal internet without Radmin/Hamachi, port 25567 (UDP & TCP) has to be forwarded in your router. If you don't know how to do that, just use Radmin VPN.

### Is using Hamachi or Radmin VPN legal?
Yes. They are just virtual private network tools for local multiplayer and completely legal.

### What Godot version do I need?
You need **Godot 4.4 or newer**. 
Godot 4.2 and older will not work and will throw parse errors because they are missing newer engine features we use. Everyone in the session should ideally be on the exact same Godot version.

### Things look desynced or a node didn't update
Close the scene tab and reopen it, or disconnect and rejoin. It will pull the latest version of the scene from the host.

### Can this break my project files?
Yes, it can. It's early in development and unexpected bugs can happen. Keep backups or use Git version control before starting sessions.

### Where do I report bugs?
Open an issue on the GitHub repository and explain what you were doing when it broke.
