import os, sys
root = sys.argv[1]
# (container expression, relative dir, folder name)
mapping = [
  ("game:GetService('ReplicatedStorage')", "src/shared/Momentum", "Momentum"),
  ("game:GetService('ServerScriptService')", "src/server", "MomentumServer"),
  ("game:GetService('StarterPlayer'):WaitForChild('StarterPlayerScripts')", "src/client", "MomentumClient"),
]
out = ["-- Installer for The Run to the Center of Hell momentum prototype.",
       "-- Paste this whole file into Roblox Studio's Command Bar (View > Command Bar) and press Enter.",
       "-- It (re)creates the scripts; running it again replaces the old copies.",
       "local function put(parent, folderName)",
       "  local old = parent:FindFirstChild(folderName); if old then old:Destroy() end",
       "  local f = Instance.new('Folder'); f.Name = folderName; f.Parent = parent; return f",
       "end",
       "local function script(folder, class, name, source)",
       "  local s = Instance.new(class); s.Name = name; s.Source = source; s.Parent = folder; return s",
       "end"]
for container, rel, name in mapping:
    out.append(f"do local f = put({container}, '{name}')")
    d = os.path.join(root, rel)
    for fn in sorted(os.listdir(d)):
        if not fn.endswith(".luau"): continue
        src = open(os.path.join(d, fn)).read()
        assert "]=====]" not in src
        if fn.endswith(".server.luau"): cls, nm = "Script", fn[:-len(".server.luau")]
        elif fn.endswith(".client.luau"): cls, nm = "LocalScript", fn[:-len(".client.luau")]
        else: cls, nm = "ModuleScript", fn[:-len(".luau")]
        out.append(f"script(f, '{cls}', '{nm}', [=====[{src}]=====])")
    out.append("end")
out.append("print('[Momentum] installed. Press Play (F5) to test.')")
open(os.path.join(root, "InstallInStudio.luau"), "w").write("\n".join(out) + "\n")
