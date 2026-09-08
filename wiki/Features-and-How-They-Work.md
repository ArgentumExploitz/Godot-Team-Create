# Features & How They Work

Here is what the plugin actually does and how the different parts work.

## Scene Sync
- Adding, deleting, renaming, and moving nodes syncs to everyone in real-time.
- Moving objects with 2D or 3D gizmos updates their position live.
- Changing properties in the Inspector (transforms, colors, meshes, materials) syncs over the network.
- When someone selects a node, a colored outline appears around it so you know they are touching it.

## 2D and 3D Cursors
- You can see where teammates have their mice in 2D canvas and 3D viewport.
- Each cursor has the person's username and their chosen color.
- It tracks world position, so zooming in or panning doesn't mess up cursor alignment.

## Script Sync
- Editing GDScript files syncs line changes live.
- You can see collaborator carets and text selections.
- Carets fade out when you type on the same line as someone else so their cursor doesn't block the code you are trying to read.

## Team Chat
- Click **Team Chat** in the bottom panel to chat.
- Messages are virtualized in batches so having a long chat won't lag your editor.
- **Pinned messages:** There is a button at the top right of the chat window for pinned messages so important stuff doesn't get lost in the scroll.
- **Images:** Disabled by default so big files don't spam. Can be toggled on with `/chatimgs true`.
