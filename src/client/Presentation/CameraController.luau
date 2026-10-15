--!strict
local CameraMath = require("./CameraMath")

local function new()
	local captured: { [Camera]: any } = {}
	local destroyed = false
	local function update(heroX: number, length: number)
		if destroyed then
			return
		end
		local camera = workspace.CurrentCamera
		if not camera then
			return
		end
		if not captured[camera] then
			captured[camera] = {
				cameraType = camera.CameraType,
				subject = camera.CameraSubject,
				cframe = camera.CFrame,
				focus = camera.Focus,
				fov = camera.FieldOfView,
				fovMode = camera.FieldOfViewMode,
			}
		end
		local viewport = camera.ViewportSize
		local frame = CameraMath.compute(heroX, length, viewport.X / math.max(1, viewport.Y), 50)
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfViewMode = Enum.FieldOfViewMode.Vertical
		camera.FieldOfView = 50
		local focus = Vector3.new(frame.centre, 2, 0)
		camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, 10, frame.distance), focus)
		camera.Focus = CFrame.new(focus)
	end
	local function destroy()
		if destroyed then
			return
		end
		destroyed = true
		for camera, original in captured do
			if camera.Parent then
				camera.CameraType = original.cameraType
				camera.CameraSubject = original.subject
				camera.CFrame = original.cframe
				camera.Focus = original.focus
				camera.FieldOfViewMode = original.fovMode
				camera.FieldOfView = original.fov
			end
		end
		table.clear(captured)
	end
	return { update = update, destroy = destroy }
end
return table.freeze({ new = new })
