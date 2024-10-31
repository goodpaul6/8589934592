package game

import rl "vendor:raylib"

main :: proc() {
	rl.InitWindow(640, 360, "8589934592")

	camera := rl.Camera3D {
		fovy       = 45,
		position   = {10, 10, 10},
		target     = {0, 0, 0},
		projection = .PERSPECTIVE,
		up         = {0, 1, 0},
	}

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()

		rl.ClearBackground(rl.RAYWHITE)

		rl.BeginMode3D(camera)

		rl.DrawCube({0, 0, 0}, 1.0, 1.0, 1.0, rl.RED)
		rl.DrawGrid(10, 1.0)

		rl.EndMode3D()

		rl.EndDrawing()
	}
}
