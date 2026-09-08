# Features & How They Work 🛠️

Here's everything Team Create does under the hood and how to use all the cool features.

---

## 🌳 1. Live Scene Editing
- **Real-Time Nodes:** When you add, delete, rename, or reparent a node in the scene tree, it instantly updates on everyone else's screen.
- **Transforms & Gizmos:** Move, rotate, or scale any 2D or 3D node and teammates see it glide across the screen in real-time.
- **Properties & Materials:** Changing numbers in the Inspector, swapping meshes (Box, Sphere, etc.), or editing material colors syncs immediately.
- **Selection Outlines:** When a teammate selects a node, a box in their color appears around it so you know what they're working on and don't accidentally fight over the same object.

---

## 🖱️ 2. 2D & 3D Collaborator Cursors
- **See Teammates Live:** You can see exactly where your teammates are looking and pointing in the 2D canvas and 3D viewport.
- **Name Tags:** Each cursor has a neat little username label tinted with that user's chosen color.
- **Accurate World Space:** Cursors match the actual scene coordinates no matter how far someone is zoomed in or panned away.

---

## 📝 3. Collaborative Script Editing
- **Live Code Sync:** When you type in a `.gd` script, your changes sync with teammates automatically.
- **Collaborator Carets:** You can see where everyone's blinking cursor and text selections are.
- **Smart Caret Transparency:** Ever had someone's big cursor block the word you're trying to read? Team Create fades out other players' carets when you're on the same or adjacent lines so you can always see what you're writing!

---

## 💬 4. In-Editor Team Chat & Pinned Messages
- **Bottom Panel:** Click **Team Chat** at the bottom of the editor to chat with your team without leaving Godot.
- **Fast & Lightweight:** Chat history is virtualized (rendered in smart batches of 40) so even huge conversations won't lag your editor.
- **📌 Pinned Messages:** Click the **📌 Pinned** button in the top right of the chat window to view or unpin important project notes, to-dos, or links without cluttering the chat feed.
- **Image Sharing:** You can drop or attach images straight into the chat! *(Turned off by default so random huge files don't spam you; turn it on anytime with `/chatimgs true`).*
