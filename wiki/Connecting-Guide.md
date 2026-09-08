# Connecting Guide 🌐

Here are all the ways you and your buddies can connect to each other. Pick whichever is easiest for you!

---

## 1. LAN Connection (Same Wi-Fi / House)

If you're in the same room or on the same local network:

### Host:
1. Open the **Team Create** dock in Godot.
2. Pick a username and color.
3. Click **Host LAN**.
4. Open your command prompt, type `ipconfig`, and find your IPv4 address (like `192.168.1.50`). Give this to your friend.

### Joiner:
1. Open the **Team Create** dock.
2. Type the Host's local IP address in the box (e.g. `192.168.1.50`).
3. Click **Join**. That's it!

---

## 2. Hamachi or Radmin VPN (No Port Forwarding needed!)

Don't have access to your router settings or don't want to mess with port forwarding? Use a virtual LAN tool like **Radmin VPN** or **LogMeIn Hamachi**. They are 100% free and totally legal.

### Setup (Takes 2 minutes):
1. Both you and your friends download **Radmin VPN** (or Hamachi) and install it.
2. **Host:** Click **Create Network**, give it a name and password, and tell your friends.
3. **Friends:** Click **Join Network**, type the name and password.
4. Now you're in the same virtual room!
5. **Joiner:** Right-click the Host in Radmin/Hamachi and click **Copy IP address** (it usually looks like `26.x.x.x` or `25.x.x.x`).
6. In Godot's Team Create dock, paste that IP and hit **Join**!

> [!TIP]
> This is usually the easiest way to play with friends over the internet without touching your router.

---

## 3. Port Forwarding (Direct Internet)

If you have access to your router and want a direct connection without third-party apps:

1. **Host:** Log into your router and forward **Port 25567** (both **UDP** and **TCP**) to your PC's local IP.
2. Make sure Godot is allowed in your Windows Firewall.
3. Find your public IP address (just google "what is my ip").
4. Click **Host LAN** in the dock.
5. **Friends:** Enter your public IP in the dock and hit **Join**.

---

## 4. Headless Dedicated Server (24/7 Hosting)

Want a server running in the background without keeping the Godot editor open?

1. Open Godot -> **Team Create** dock.
2. Scroll to the bottom and click **Export Headless Server**.
3. Choose a folder. It exports everything you need with launch scripts!
4. Run:
   - **Windows:** Double click `start_server.bat`
   - **Linux:** Run `./start_server.sh`
5. Connect to it like normal using the server's IP address!
