package game

import sa "core:container/small_array"
import "core:encoding/cbor"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:os"
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

PosUp :: struct {
	pos: rl.Vector3,
	up:  rl.Vector3,
}

VIEW_POS := [View]PosUp {
	.TOP = PosUp{pos = {0, CAM_DIST, 0}, up = {0, 0, -1}},
	.BOTTOM = PosUp{pos = {0, -CAM_DIST, 0}, up = {0, 0, -1}},
	.LEFT = PosUp{pos = {CAM_DIST, 0, 0}, up = {0, 1, 0}},
	.RIGHT = PosUp{pos = {-CAM_DIST, 0, 0}, up = {0, 1, 0}},
	.FRONT = PosUp{pos = {0, 0, CAM_DIST}, up = {0, 1, 0}},
	.BACK = PosUp{pos = {0, 0, -CAM_DIST}, up = {0, 1, 0}},
}

GRID_LEN :: GRID_SIZE * GRID_SIZE * GRID_SIZE

Grid_Value :: struct {
	src_value:  int,
	// These are only changed when the value is shifted
	dest_pos:   [3]int,
	dest_value: int,
}

Grid :: [GRID_LEN]Grid_Value

// Sets src_value to dest_value and moves the value to it's dest_pos in the grid
grid_settle :: proc(grid: ^Grid) {
	for x := 0; x < GRID_SIZE; x += 1 {
		for y := 0; y < GRID_SIZE; y += 1 {
			for z := 0; z < GRID_SIZE; z += 1 {
				idx := x * GRID_SIZE * GRID_SIZE + y * GRID_SIZE + z
				value := &grid[idx]

				// If the grid value hasn't moved, no need to do anything
				if grid[idx].dest_pos == {x, y, z} {
					continue
				}

				dest_idx :=
					value.dest_pos.x * GRID_SIZE * GRID_SIZE +
					value.dest_pos.y * GRID_SIZE +
					value.dest_pos.z

				// Update the dest value
				grid[dest_idx] = {
					src_value  = value.dest_value,
					dest_pos   = value.dest_pos,
					dest_value = value.dest_value,
				}

				// Clear out where the grid value moved from
				value.src_value = 0
				value.dest_pos = {x, y, z}
				value.dest_value = 0
			}
		}
	}
}

// If this returns -1, there are no empty spots
rand_zero_index :: proc(grid: ^Grid) -> int {
	possible_indices: sa.Small_Array(GRID_LEN, int)

	for value, i in grid {
		if value.src_value == 0 {
			sa.push(&possible_indices, i)
		}
	}

	if possible_indices.len == 0 {
		return -1
	}

	return rand.choice(sa.slice(&possible_indices))
}

delta2_to_delta3 :: proc(d2: [2]int, view: View) -> [3]int {
	d3: [3]int

	switch view {
	case .TOP:
		d3.x = d2.x
		d3.z = d2.y
	case .BOTTOM:
		d3.x = -d2.x
		d3.z = d2.y
	case .LEFT:
		d3.z = -d2.x
		d3.y = -d2.y
	case .RIGHT:
		d3.z = d2.x
		d3.y = -d2.y
	case .FRONT:
		d3.x = d2.x
		d3.y = -d2.y
	case .BACK:
		d3.x = -d2.x
		d3.y = -d2.y
	}

	return d3
}

// Returns true if we did do a shift
shift_values :: proc(grid: ^Grid, delta: [3]int) -> bool {
	// Look at every value and then see if moving it by delta is possible.
	// It's possible if the index is empty or if the index contains the same
	// value.
	//
	// If so, we shift the value: set the value at dest to 2 * value and set current
	// pos to 0.

	shift_count := 0

	// If this is true at an index then it should not be merged again in this shift
	already_merged: [GRID_LEN]bool

	for x := 0; x < GRID_SIZE; x += 1 {
		for y := 0; y < GRID_SIZE; y += 1 {
			for z := 0; z < GRID_SIZE; z += 1 {
				src_idx := x * GRID_SIZE * GRID_SIZE + y * GRID_SIZE + z
				value := &grid[src_idx]

				if value.src_value == 0 || value.dest_value == 0 {
					continue
				}

				// Keep moving while we can
				for {
					// We actually want to use the position its shifted to (if at all) in order to determine
					// where it's at
					cur_pos := value.dest_pos
					dest_pos := [3]int {
						cur_pos.x + delta.x,
						cur_pos.y + delta.y,
						cur_pos.z + delta.z,
					}

					if dest_pos.x < 0 ||
					   dest_pos.x >= GRID_SIZE ||
					   dest_pos.y < 0 ||
					   dest_pos.y >= GRID_SIZE ||
					   dest_pos.z < 0 ||
					   dest_pos.z >= GRID_SIZE {
						// Out of range, stop moving
						break
					}

					dest_idx :=
						dest_pos.x * (GRID_SIZE * GRID_SIZE) + dest_pos.y * GRID_SIZE + dest_pos.z

					dest_value := &grid[dest_idx]

					if dest_value.src_value == 0 {
						// While there's empties, keep moving
						value.dest_pos = dest_pos

						shift_count += 1
					} else if dest_value.src_value == value.src_value &&
					   !already_merged[dest_idx] {
						// Only let this merge again if we haven't already merged the value here hence
						// the already_merged

						value.dest_pos = dest_pos
						value.dest_value = value.src_value * 2

						// The spot we moved to is about to go to 0
						dest_value.dest_value = 0

						shift_count += 1

						already_merged[dest_idx] = true

						// When we merge, stop
						break
					} else {
						break
					}
				}
			}
		}
	}


	return shift_count > 0
}

main :: proc() {
	rl.InitWindow(600, 600, "8589934592")
	defer rl.CloseWindow()

	view := View.TOP
	dest_view := View.TOP
	view_trans_time_left := f32(0)

	VIEW_TRANS_TIME :: f32(0.5)

	camera := rl.Camera3D {
		fovy       = 45,
		position   = {-5, 0, 0},
		target     = {0, 0, 0},
		projection = .PERSPECTIVE,
		up         = {0, 1, 0},
	}

	Num_Texture :: struct {
		value:   int,
		texture: rl.RenderTexture,
	}

	num_textures: [dynamic]Num_Texture

	cube_mesh := rl.GenMeshCube(0.8, 0.8, 0.8)
	defer rl.UnloadMesh(cube_mesh)

	SAVE_FILENAME :: "cubed.save"

	grid: Grid

	{
		data, ok := os.read_entire_file(SAVE_FILENAME, context.temp_allocator)
		if ok {
			err := cbor.unmarshal(string(data), &grid)
			if err != nil {
				fmt.eprintln("Failed to load save. Delete it.")
			}
		} else {
			grid_settle(&grid)

			idx := rand_zero_index(&grid)
			grid[idx].src_value = 2
			grid[idx].dest_value = 2
		}
	}

	SHIFT_TIME :: f32(0.2)
	shift_time_left := f32(0)

	for !rl.WindowShouldClose() {
		if view == dest_view {
			// At rest rn, so let the user change view

			if rl.IsKeyPressed(.ONE) {
				dest_view = .TOP
			}

			if rl.IsKeyPressed(.TWO) {
				dest_view = .BOTTOM
			}

			if rl.IsKeyPressed(.THREE) {
				dest_view = .LEFT
			}

			if rl.IsKeyPressed(.FOUR) {
				dest_view = .RIGHT
			}

			if rl.IsKeyPressed(.FIVE) {
				dest_view = .BACK
			}

			if rl.IsKeyPressed(.SIX) {
				dest_view = .FRONT
			}

			if dest_view != view {
				view_trans_time_left += VIEW_TRANS_TIME
			}
		} else if view_trans_time_left > 0 {
			view_trans_time_left -= rl.GetFrameTime()
			if view_trans_time_left <= 0 {
				view = dest_view
			}
		}

		d2: [2]int

		if shift_time_left <= 0 {
			if rl.IsKeyPressed(.LEFT) {
				d2.x = -1
			}

			if rl.IsKeyPressed(.RIGHT) {
				d2.x = 1
			}

			if rl.IsKeyPressed(.UP) {
				d2.y = -1
			}

			if rl.IsKeyPressed(.DOWN) {
				d2.y = 1
			}

			if d2.x != 0 || d2.y != 0 {
				d3 := delta2_to_delta3(d2, view)

				did_shift := shift_values(&grid, d3)

				if did_shift {
					shift_time_left += SHIFT_TIME
				}
			}
		} else {
			shift_time_left -= rl.GetFrameTime()

			if shift_time_left <= 0 {
				shift_time_left = 0
				grid_settle(&grid)

				// Spawn block in random pos; must do it after settle
				// because otherwise we might overwrite values being shifted
				empty_idx := rand_zero_index(&grid)

				if empty_idx < 0 {
					// TODO(Apaar): Check if game is possible or end game if not
				} else {
					// TODO(Apaar): Also spawn 4s
					grid[empty_idx].src_value = 2
					grid[empty_idx].dest_value = 2
				}

				data, err := cbor.marshal(grid)

				if err != nil || !os.write_entire_file(SAVE_FILENAME, data) {
					fmt.eprintf("Failed to write to file cubed.save")
				}
			}
		}

		if view == dest_view {
			camera.position = VIEW_POS[view].pos
			camera.up = VIEW_POS[view].up
		} else {
			t := view_trans_time_left / VIEW_TRANS_TIME
			camera.position = VIEW_POS[view].pos * t + VIEW_POS[dest_view].pos * (1.0 - t)
			camera.up = VIEW_POS[view].up * t + VIEW_POS[dest_view].up * (1.0 - t)
		}

		rl.BeginDrawing()

		rl.ClearBackground(rl.RAYWHITE)

		rl.BeginMode3D(camera)

		east_out_bounce :: proc(x: f32) -> f32 {
			n1 := f32(7.5625)
			d1 := f32(2.75)

			if x < 1 / d1 {
				return n1 * x * x
			} else if x < 2 / d1 {
				y := x - 1.5 / d1
				return n1 * y * y + 0.75
			} else if x < 2.5 / d1 {
				y := x - 2.25 / d1
				return n1 * y * y + 0.9375
			} else {
				y := x - 2.625 / d1
				return n1 * y * y + 0.984375
			}
		}

		// easeOutCubic
		shift_time_t := 1 - math.pow(1 - (1 - shift_time_left / SHIFT_TIME), 3)

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

					num := shift_time_t > 0.5 ? value.dest_value : value.src_value

					if num == 0 {
						continue
					}

					texture: ^rl.RenderTexture

					for &num_texture in num_textures {
						if num_texture.value == num {
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

						value_to_color := [?]struct {
							value: int,
							color: u32,
						} {
							{value = 2, color = 0xeee4daff},
							{value = 4, color = 0xede0c8ff},
							{value = 8, color = 0xf2b179ff},
							{value = 16, color = 0xf59563ff},
							{value = 32, color = 0xf67c5fff},
							{value = 64, color = 0xf65e3bff},
							{value = 128, color = 0xedcf72ff},
							{value = 256, color = 0xedcc61ff},
							{value = 512, color = 0xedc850ff},
							{value = 1024, color = 0xedc53fff},
							{value = 2048, color = 0xedc22eff},
							{value = 4096, color = 0x3c3a32ff},
						}

						// Blend between number color values when shifting
						src_color: rl.Color
						dest_color: rl.Color

						blend_num := int(
							math.ceil(
								f32(value.src_value) * (1 - shift_time_t) +
								f32(value.dest_value) * shift_time_t,
							),
						)

						for vc in value_to_color {
							if vc.value == blend_num {
								src_color = rl.GetColor(vc.color)
								dest_color = rl.GetColor(vc.color)
								break
							} else if vc.value < blend_num {
								src_color = rl.GetColor(vc.color)
							} else if vc.value > blend_num {
								dest_color = rl.GetColor(vc.color)
								break
							}
						}

						blended_color := rl.ColorFromNormalized(
							rl.ColorNormalize(src_color) * (1 - shift_time_t) +
							rl.ColorNormalize(dest_color) * shift_time_t,
						)

						blended_color.a = 0xff

						rl.ClearBackground(blended_color)

						fmt.println(num, src_color, dest_color, value)

						str := strings.clone_to_cstring(
							fmt.tprintf("%d", num),
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

						append(&num_textures, Num_Texture{value = num, texture = r_texture})

						texture = &r_texture
					}

					dest_pos := rl.Vector3 {
						f32(value.dest_pos.x - GRID_SIZE / 2) + 0.5,
						f32(value.dest_pos.y - GRID_SIZE / 2) + 0.5,
						f32(value.dest_pos.z - GRID_SIZE / 2) + 0.5,
					}

					mat := rl.LoadMaterialDefault()
					rl.SetMaterialTexture(&mat, .ALBEDO, texture.texture)

					blended_pos := pos * (1 - shift_time_t) + dest_pos * shift_time_t

					scale := f32(1.0)

					// It's gonna shrink away
					if value.dest_value == 0 {
						scale = 1 - shift_time_t
					}

					rl.DrawMesh(
						cube_mesh,
						mat,
						rl.MatrixTranslate(blended_pos.x, blended_pos.y, blended_pos.z) *
						rl.MatrixScale(scale, scale, scale),
					)
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
