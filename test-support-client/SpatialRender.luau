--!strict
-- Engine object/camera smoke test. Does not assert a screenshot or physical input occurred.
return function(env: any, check: any)
	local camera = workspace.CurrentCamera :: Camera
	local before = {
		kind = camera.CameraType,
		cf = camera.CFrame,
		focus = camera.Focus,
		fov = camera.FieldOfView,
		subject = camera.CameraSubject,
	}
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpatialRenderFixture"
	gui.Parent = game.Players.LocalPlayer.PlayerGui
	local renderer = env.WorldView.new(gui, env.catalog)
	local view: any = {
		mode = "Normal",
		spatial = true,
		heroKind = "light",
		auraRadius = 110,
		entities = {},
		objects = {},
		traps = {},
	}
	local function entity(id: number, kind: string, n: number, team: number)
		table.insert(view.entities, {
			id = id,
			kind = kind,
			n = n,
			team = team,
			dir = 1,
			x = 100 + id * 25,
			z = id % 3 * 20,
			y = 165,
			hp = 100,
			maxHp = 100,
		})
	end
	entity(1, "Hero", 0, 1)
	for n = 1, 9 do
		entity(1 + n, "Unit", n, 1)
	end
	for n = 1, 20 do
		entity(10 + n, "Enemy", n, 2)
	end
	for n = 1, 10 do
		entity(30 + n, "Boss", n, 2)
	end
	for n = 1, 9 do
		entity(40 + n, "Totem", n, 1)
	end
	entity(50, "Castle", 1, 2)
	entity(51, "Wagon", 1, 1)
	entity(52, "Horse", 1, 2)
	view.objects = {
		{ id = 101, kind = "Straight", row = 268, x = 180, z = 40 },
		{ id = 102, kind = "Lob", row = 262, x = 200, z = -40, t = 0.5 },
	}
	renderer.render(view, 1, 1 / 60)
	local candidate = workspace:FindFirstChild("LanternExpedition3D")
	check("3d-render-real-folder", true, candidate ~= nil, 0)
	local arena = candidate :: Folder
	check("3d-render-entity-models", 52, renderer.count(), 0)
	local hero = arena:FindFirstChild("Entity_1") :: Model
	check("3d-render-hero-model", true, hero:IsA("Model"), 0)
	check("3d-render-server-coordinate-x", 15, hero:GetPivot().Position.X, 0)
	check(
		"3d-render-server-coordinate-z",
		true,
		math.abs(hero:GetPivot().Position.Z - 2.4) < 0.001,
		0
	)
	check("3d-render-camera-follow", "Scriptable", camera.CameraType.Name, 0)
	check(
		"3d-render-camera-focus",
		true,
		(camera.Focus.Position - Vector3.new(15, 1.8, 2.4)).Magnitude < 0.001,
		0
	)
	check(
		"3d-render-spell-depth",
		true,
		math.abs((arena:FindFirstChild("Spell_101") :: Part).Position.Z - 4.8) < 0.001,
		0
	)
	local secure = true
	for _, o in arena:GetDescendants() do
		if o:IsA("BasePart") then
			secure = secure
				and o.Anchored
				and not o.CanCollide
				and not o.CanTouch
				and not o.CanQuery
		end
	end
	check("3d-render-no-physics-authority", true, secure, 0)
	view.entities = { view.entities[1] }
	view.objects = {}
	view.heroKind = "shadow"
	renderer.render(view, 1, 1 / 60)
	check("3d-render-removed-models-cleaned", 1, renderer.count(), 0)
	check("3d-render-removed-shots-cleaned", nil, arena:FindFirstChild("Spell_101"), 0)
	renderer.clear()
	check("3d-render-folder-cleanup", nil, workspace:FindFirstChild("LanternExpedition3D"), 0)
	check("3d-render-camera-type-restored", before.kind, camera.CameraType, 0)
	check("3d-render-camera-cframe-restored", before.cf, camera.CFrame, 0)
	check("3d-render-camera-focus-restored", before.focus, camera.Focus, 0)
	check("3d-render-camera-fov-restored", before.fov, camera.FieldOfView, 0)
	renderer.clear()
	renderer.destroy()
	gui:Destroy()
	check("3d-render-repeat-cleanup", nil, workspace:FindFirstChild("LanternExpedition3D"), 0)
end
