package game

import sa "core:container/small_array"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"

GRID_SIZE :: 4

View :: enum {
	TOP,
	BOTTOM,
	LEFT,
	RIGHT,
	FRONT,
	BACK,
}

CAM_DIST :: 10

VIEW_POS := [View]rl.Vector3 {
	// HACK(Apaar): The 0.01 is because it disappears if I don't, maybe some kind of rounding error or smth idk
	.TOP    = {0, CAM_DIST, 0.01},
	.BOTTOM = {0, -CAM_DIST, -0.01},
	.LEFT   = {CAM_DIST, 0, 0.01},
	.RIGHT  = {-CAM_DIST, 0, 0.01},
	.FRONT  = {0.01, 0, CAM_DIST},
	.BACK   = {0.01, 0, -CAM_DIST},
}

GRID_LEN :: GRID_SIZE * GRID_SIZE * GRID_SIZE
Grid :: [GRID_LEN]int

// If this returns -1, there are no empty spots
rand_zero_index :: proc(grid: ^Grid) -> int {
	possible_indices: sa.Small_Array(GRID_LEN, int)

	for value, i in grid {
		if value == 0 {
			sa.push(&possible_indices, i)
		}
	}

	if possible_indices.len == 0 {
		return -1
	}

	return rand.choice(sa.slice(&possible_indices))
}

main :: proc() {
	rl.InitWindow(600, 600, "8589934592")
	defer rl.CloseWindow()

	view := View.TOP

	camera := rl.Camera3D {
		fovy       = 45,
		position   = {-5, 0, 0},
		target     = {0, 0, 0},
		projection = .PERSPECTIVE,
		up         = {0, 1, 0},
	}

	grid: Grid

	{
		idx := rand_zero_index(&grid)
		grid[idx] = 2
	}

	Num_Texture :: struct {
		value:   int,
		texture: rl.RenderTexture,
	}

	num_textures: [dynamic]Num_Texture

	cube_mesh := rl.GenMeshCube(0.8, 0.8, 0.8)
	defer rl.UnloadMesh(cube_mesh)

	for !rl.WindowShouldClose() {
		if rl.IsKeyPressed(.ONE) {
			view = .TOP
		}

		if rl.IsKeyPressed(.TWO) {
			view = .BOTTOM
		}

		if rl.IsKeyPressed(.THREE) {
			view = .LEFT
		}

		if rl.IsKeyPressed(.FOUR) {
			view = .RIGHT
		}

		if rl.IsKeyPressed(.FIVE) {
			view = .BACK
		}

		if rl.IsKeyPressed(.SIX) {
			view = .FRONT
		}

		camera.position = VIEW_POS[view]

		rl.BeginDrawing()

		rl.ClearBackground(rl.RAYWHITE)

		rl.BeginMode3D(camera)

		for x := 0; x < GRID_SIZE; x += 1 {
			for y := 0; y < GRID_SIZE; y += 1 {
				for z := 0; z < GRID_SIZE; z += 1 {
					pos := rl.Vector3 {
						f32(x - GRID_SIZE / 2) + 0.5,
						f32(y - GRID_SIZE / 2) + 0.5,
						f32(z - GRID_SIZE / 2) + 0.5,
					}

					rl.DrawCubeWires(
						pos,
						1,
						1,
						1,
						{
							u8(f32(x) / f32(GRID_SIZE) * 255),
							u8(f32(y) / f32(GRID_SIZE) * 255),
							u8(f32(z) / f32(GRID_SIZE) * 255),
							u8(255),
						},
					)

					value := grid[x * GRID_SIZE * GRID_SIZE + y * GRID_SIZE + z]

					if value == 0 {
						continue
					}

					texture: ^rl.RenderTexture

					for &num_texture in num_textures {
						if num_texture.value == value {
							texture = &num_texture.texture
						}
					}

					if texture == nil {
						tex_w := i32(128)
						tex_h := i32(128)
						font_size := i32(36)

						// Draw the number to a texture
						r_texture := rl.LoadRenderTexture(tex_w, tex_h)

						rl.BeginTextureMode(r_texture)

						rl.ClearBackground(rl.WHITE)

						str := strings.clone_to_cstring(
							fmt.tprintf("%d", value),
							context.temp_allocator,
						)

						str_size := rl.MeasureTextEx(rl.GetFontDefault(), str, f32(font_size), 0)

						rl.DrawText(
							str,
							tex_w / 2 - i32(str_size.x / 2),
							tex_h / 2 - i32(str_size.y / 2),
							font_size,
							rl.BLACK,
						)

						rl.EndTextureMode()

						append(&num_textures, Num_Texture{value = value, texture = r_texture})

						texture = &r_texture
					}

					mat := rl.LoadMaterialDefault()
					rl.SetMaterialTexture(&mat, .ALBEDO, texture.texture)

					rl.DrawMesh(cube_mesh, mat, rl.MatrixTranslate(pos.x, pos.y, pos.z))
				}
			}
		}

		rl.EndMode3D()

		view_name, _ := reflect.enum_name_from_value(view)

		rl.DrawText(
			strings.clone_to_cstring(view_name, context.temp_allocator),
			10,
			10,
			40,
			rl.BLACK,
		)

		rl.EndDrawing()

		free_all(context.temp_allocator)
	}
}
