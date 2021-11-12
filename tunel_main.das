require daslib/media
require daslib/functional
require daslib/algorithm
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

var
    tunel_edge_color_vec: float3
    tunel_edge_center_vec: float3
    backgroud_color_vec: float3
    ball_color = 0x4C9649

    ball_pos: float3
    ball_base_pos: float3
    ball_radius: float
    camera_pos: float3
    center_view: float3
    up: float3
    right: float3
    segments_control_points : array<float3>
    segments_edge_points : array<array<float3>>
    current_segment: int
    one_segment_point_back: float3
    slice_ball_pos: float2
    slice_ball_vel: float2
    move_speed: float
    shadow_scale: float
    shadow_pos: float3
    crystals: array<int2>
    current_time: float
    seed: int4
    gathered_crystals:int
    ball_z: float
    walls: array<int2>
    restart = false
    seconds_to_restart: float
    win = false
    start_segment = 0
    cut_scene: bool
    ball_vector: float3
    run_engine: bool
    cut_scene_time:float
    show_names: bool
    start_ship: bool
    ship_velocity: float
    show_thanks: bool
    fast_panels: array<int2>
    slow_panels: array<int2>
    far_fog: Image
    stub_texture: Image
    paused: bool

let
    segment_width = 1.0
    segments_count = 30
    sectors_count = 15
    tunel_edge_center = 0xE0E0E0
    backgroud_color = 0x2B2B30
    base_tunel_edge_color = 0x4B4BCE
    fast_tunel_edge_color = 0x4BCE61
    slow_tunel_edge_color = 0xC74949
    fog_color = 0x6A0080
    base_move_speed = 4.0
    crystal_scale = 0.25
    crystals_to_win = 1000
    wall_height = 0.5
    restart_timeout = 5.0
    run_engine_timing = 1.0
    names_timing = 3.0
    names_display_duration = 1.5
    starship_start_timing = 9.0
    thanks_timing = 10.0
    high_speed = 8.0
    low_speed = 3.0

def reset
    ball_radius = 0.35
    camera_pos = float3(0.0, 0.0, 0.0)
    center_view = float3(0, 0, 1)
    up = float3(0, 1, 0)
    right = float3(1, 0, 0)
    current_segment = 0
    one_segment_point_back = generate_point(-1.0)
    slice_ball_pos = float2(0, 0)
    slice_ball_vel = float2(0, 0)
    move_speed = base_move_speed
    shadow_scale = 0.9
    current_time = 0.0
    seed = int4(762, 22, 3, 4)
    crystals |> clear()
    walls |> clear()
    gathered_crystals = 0
    win = false
    start_segment = 0
    cut_scene = false
    run_engine = false
    cut_scene_time = 0.0
    start_ship = false
    ship_velocity = 0.0
    show_thanks = false
    fast_panels |> clear()
    slow_panels |> clear()
    paused = false

    segments_control_points |> resize(segments_count)
    for i in range(segments_count)
        segments_control_points[i] = generate_point(float(i))
    segments_edge_points |> resize(segments_count)
    for i in range(segments_count)
        segments_edge_points[i] <- generate_edge_points(segments_control_points[i], segments_control_points[(i + 1) % segments_count])

    ball_base_pos = segments_control_points[2]


def color_to_vec(color)
    return float3((color >> 16u) & 0xFF, (color >> 8u) & 0xFF, color & 0xFF) / 255.0

def vec_to_color(vec)
    return (uint(vec.x * 255.0) << 16u) | (uint(vec.y * 255.0) << 8u) | (uint(vec.z * 255.0) << 0u)

def gen_point_for_angle(pos, next_pos, angle)
    let segment_dir = normalize(next_pos - pos)
    let segment_right = normalize(cross(segment_dir, up))
    let segment_up = normalize(cross(segment_right, segment_dir))
    return segment_width * (cos(angle) * segment_right + sin(angle) * segment_up) + pos

def generate_edge_points(pos, next_pos)
    var points: array<float3>
    for i in range(sectors_count)
        var angle = float(i) / float(sectors_count) * math::PI * 2.0
        points |> push(gen_point_for_angle(pos, next_pos, angle))
    return <- points

def generate_point(z_offset)
    let x = sin(z_offset) * 0.15
    let y = cos(z_offset * 0.4) * 0.15
    return float3(x, y, z_offset)

def project_point(point)
    let shifted = point - camera_pos
    return project_shifted(shifted)

def project_shifted(point)
    let in_camera_space = float3(
        dot(point, right),
        dot(point, up),
        dot(point, center_view)
    )

    let in_clip_space = in_camera_space / in_camera_space.z
    let aspect_ratio = float(get_screen_width()) / float(get_screen_height())
    return (in_clip_space.xy * float2(1, -1) + float2(aspect_ratio, 1.0)) * 0.5 * float(get_screen_height())

def unproj_dir(position)
    let aspect_ratio = float(get_screen_width()) / float(get_screen_height())
    let in_clip_space = (position / float(get_screen_height()) * 2.0 - float2(aspect_ratio, 1.0)) * float2(-1, -1)
    return normalize(float3(in_clip_space, 1.0))

// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize
    set_antialiasing(4)
    tunel_edge_center_vec = color_to_vec(tunel_edge_center)
    backgroud_color_vec = color_to_vec(backgroud_color)

    far_fog <- create_image(100, 100)
    far_fog |> set_image_smooth(true)
    for iy in range(100)
        for ix in range(100)
            let x = float(ix - 50) / 50.0
            let y = float(iy - 50) / 50.0
            let alpha = uint(lerp(0.0, 255.0, pow(1.0 - clamp(length(float2(x, y)), 0.0, 1.0), 0.75))) << 24u
            far_fog |> set_pixel(ix, iy, fog_color | alpha)

    stub_texture <- create_image(1, 1)
    stub_texture |> set_pixel(0, 0, 0xFFFFFFFF)

    reset()

    set_window_title("Tunel")
    return

def easeInOutCubic(x)
    return x < 0.5 ? 4.0 * x * x * x : 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0;

def easeInOutSine(x)
    return -(cos(math::PI * x) - 1.0) / 2.0;


def get_crystal_center(segment_id, sector_idx)
    let cell_center = (
        segments_edge_points[segment_id][sector_idx]
        + segments_edge_points[segment_id][(sector_idx + 1) % sectors_count]
        + segments_edge_points[(segment_id + 1) % segments_count][(sector_idx + 1) % sectors_count]
        + segments_edge_points[(segment_id + 1) % segments_count][sector_idx]
    ) * 0.25
    let seg_normal = normalize(cross(
        segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx],
        + segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]
    ))
    return cell_center + seg_normal * (crystal_scale * lerp(1.7, 1.0, sin(current_time * 5.0 + float(segment_id)) * 0.5 + 0.5))

def get_wall_center(segment_id, sector_idx)
    let seg_normal = normalize(cross(
        segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx],
        + segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]
    ))
    return (
        (segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] + segments_edge_points[segment_id][sector_idx]) * 0.5
        + seg_normal * 0.5 * wall_height
    )

def set_up_cut_scene
    cut_scene = true
    ball_vector = center_view
    up = normalize(float3(0, 1, 1))
    center_view = normalize(cross(center_view, up))
    right = cross(center_view, up)
    camera_pos = ball_pos - center_view * 10.0
    current_segment = (current_segment + 4) % segments_count


// this function is called to update game data,
// dt - time elapsed since the previous update (in seconds)
[export]
def act(dt: float)
    if paused
        return
    // paused = true

    if get_key(VK_ESCAPE)
        schedule_quit_game()

    if restart
        seconds_to_restart -= dt
        if seconds_to_restart < 0.0
            seconds_to_restart = 0.0
            restart = false
            reset()
        return

    if get_key(VK_SPACE)
        reset()

    if cut_scene
        cut_scene_time += dt
        if !run_engine
            ball_pos += dt * ball_vector * 3.0
        if cut_scene_time > run_engine_timing
            run_engine = true
        show_names = cut_scene_time > names_timing && cut_scene_time < names_timing + names_display_duration
        if cut_scene_time > starship_start_timing
            start_ship = true
        if start_ship
            ship_velocity += dt * 10.0
            ball_pos += dt * up * pow(ship_velocity, 2.0)

        if cut_scene_time > thanks_timing
            show_thanks = true

        if cut_scene_time > 15.0
            schedule_quit_game()
        return

    if get_key(VK_RIGHT)
        slice_ball_vel.x += 4.0 * dt
    if get_key(VK_LEFT)
        slice_ball_vel.x -= 4.0 * dt
    // if get_key(VK_UP)
    //     move_speed = min(move_speed + 4.0 * dt, 8.0)
    // if get_key(VK_DOWN)
    //     move_speed = max(move_speed - 4.0 * dt, lowest_move_speed)

    tunel_edge_color_vec = color_to_vec(base_tunel_edge_color)
    if move_speed > base_move_speed
        move_speed = max(move_speed - dt, base_move_speed)
        tunel_edge_color_vec = lerp(
            color_to_vec(base_tunel_edge_color),
            color_to_vec(fast_tunel_edge_color),
            (move_speed - base_move_speed) / (high_speed - base_move_speed))
    if move_speed < base_move_speed
        move_speed = min(move_speed + dt * 0.5, base_move_speed)
        tunel_edge_color_vec = lerp(
            color_to_vec(base_tunel_edge_color),
            color_to_vec(slow_tunel_edge_color),
            (base_move_speed - move_speed) / (base_move_speed - low_speed))

    let scaled_dt = dt * move_speed

    slice_ball_vel.y -= 7.0 * dt

    slice_ball_pos += slice_ball_vel * dt
    var shadow_slice_pos = slice_ball_pos
    shadow_slice_pos.y = -sqrt(1.0 - min(pow(shadow_slice_pos.x, 2.0), 0.99))
    if length(slice_ball_pos) > 1.0
        slice_ball_pos = normalize(slice_ball_pos)
        slice_ball_vel = slice_ball_vel - 2.0 * dot(slice_ball_vel, -slice_ball_pos) * -slice_ball_pos

    slice_ball_vel *= 0.99

    current_time += dt

    camera_pos += center_view * scaled_dt

    let next_segment = (current_segment + 1) % segments_count
    let next2_segment = (current_segment + 2) % segments_count
    let next3_segment = (current_segment + 3) % segments_count
    let prev_view = normalize(segments_control_points[current_segment % segments_count] - one_segment_point_back)
    let current_view = normalize(segments_control_points[next_segment] - segments_control_points[current_segment % segments_count])
    let next_view = normalize(segments_control_points[next2_segment] - segments_control_points[next_segment])
    let next2_view = normalize(segments_control_points[next3_segment] - segments_control_points[next2_segment])
    let t = ((camera_pos.z - segments_control_points[current_segment % segments_count].z)
        / (segments_control_points[next_segment].z - segments_control_points[current_segment % segments_count].z))
    let p1_view = lerp(prev_view, current_view, t)
    let p2_view = lerp(current_view, next_view, t)
    let p3_view = lerp(next_view, next2_view, t)
    let blended_view = p2_view//normalize(lerp(lerp(p1_view, p2_view, t), p3_view, t))

    center_view = blended_view // normalize(lerp(blended_view, float3(0, 0, 1), 0.5))
    right = normalize(cross(center_view, float3(0, 1, 0)))
    up = normalize(cross(right, center_view))

    ball_base_pos += center_view * scaled_dt
    ball_pos = ball_base_pos + slice_ball_pos.y * up + slice_ball_pos.x * right
    shadow_pos = ball_base_pos + shadow_slice_pos.y * up + shadow_slice_pos.x * right
    shadow_scale = lerp(0.9, 0.0, (slice_ball_pos.y + 1.0) * 0.5)
    ball_z = get_ball_z(ball_pos)

    var crystals_to_remove: array<int>
    for idx, crys in range(crystals |> length()), crystals
        let crystal_center = get_crystal_center(crys.x, crys.y)
        let radius = ball_radius + crystal_scale
        if length(crystal_center - ball_pos) < radius
            crystals_to_remove |> push(idx)

    reverse(crystals_to_remove)
    gathered_crystals += crystals_to_remove |> length()
    win = gathered_crystals >= crystals_to_win
    for to_rem_idx in crystals_to_remove
        crystals |> erase(to_rem_idx)

    for wall in walls
        let wall_center = get_wall_center(wall.x, wall.y)
        let radius = ball_radius + wall_height * 0.25
        if length(wall_center - ball_pos) < radius
            restart = true
            seconds_to_restart = restart_timeout

    for panel in fast_panels
        let panel_center = get_panel_center(panel.x, panel.y)
        let radius = ball_radius + 0.1
        if length(panel_center - ball_pos) < radius
            move_speed = 8.0

    for panel in slow_panels
        let panel_center = get_panel_center(panel.x, panel.y)
        let radius = ball_radius + 0.1
        if length(panel_center - ball_pos) < radius
            move_speed = 3.0

    let new_segment = int(camera_pos.z)
    if new_segment != current_segment
        if win
            start_segment++
            if start_segment == segments_count - 2
                set_up_cut_scene()
                return
        else
            let rounded_idx = current_segment % segments_count
            let rounded_prev_idx = (current_segment + segments_count - 1) % segments_count
            one_segment_point_back = segments_control_points[rounded_idx]
            segments_control_points[rounded_idx] = generate_point(float(current_segment + segments_count))
            segments_edge_points[rounded_prev_idx] <- generate_edge_points(segments_control_points[rounded_prev_idx], segments_control_points[rounded_idx])

            let rand_value = random::random_int(seed) % 15
            if rand_value / 3 == 0
                crystals |> push(int2(
                    (rounded_prev_idx + segments_count - 1) % segments_count,
                    random::random_int(seed) % ((sectors_count - 1) / 2) + sectors_count / 2
                ))
            if rand_value == 4
                walls |> push(int2(
                    (rounded_prev_idx + segments_count - 1) % segments_count,
                    random::random_int(seed) % sectors_count
                ))
            if rand_value / 3 == 2
                fast_panels |> push(int2(
                    (rounded_prev_idx + segments_count - 1) % segments_count,
                    random::random_int(seed) % sectors_count
                ))
            if rand_value / 3 == 3
                slow_panels |> push(int2(
                    (rounded_prev_idx + segments_count - 1) % segments_count,
                    random::random_int(seed) % sectors_count
                ))

            var filtered_crystals: array<int2>
            for crys in crystals
                if crys.x == rounded_idx
                    continue
                filtered_crystals |> push(crys)
            crystals <- filtered_crystals

            var filtered_walls: array<int2>
            for wall in walls
                if wall.x == rounded_idx
                    continue
                filtered_walls |> push(wall)
            walls <- filtered_walls

            var filtered_fast_panels: array<int2>
            for panel in fast_panels
                if panel.x == rounded_idx
                    continue
                filtered_fast_panels |> push(panel)
            fast_panels <- filtered_fast_panels

            var filtered_slow_panels: array<int2>
            for panel in slow_panels
                if panel.x == rounded_idx
                    continue
                filtered_slow_panels |> push(panel)
            slow_panels <- filtered_slow_panels

    current_segment = new_segment

    return


def draw_line(var x1, y1, x2, y2, width, base_color)
    let normal : float2 = normalize(float2(y1 - y2, x2 - x1))
    let line_half_width = max(width / 2, 1)
    let line_quart_width = max(line_half_width / 2, 1)
    for i in range(line_half_width)
        let x_start = float(x1) + float(i) * normal.x
        let y_start = float(y1) + float(i) * normal.y
        let x_finish = float(x2) + float(i) * normal.x
        let y_finish = float(y2) + float(i) * normal.y
        var color = float3(0, 0, 0)
        if i < line_quart_width
            color = lerp(tunel_edge_center_vec, base_color, float(i) / float(line_quart_width))
        else
            color = lerp(base_color, backgroud_color_vec, float(i - line_quart_width) / float(line_quart_width))
        graphics::line(x_start, y_start, x_finish, y_finish, vec_to_color(color) | 0x8f000000)

    for i in range(line_half_width)
        let x_start = float(x1) - float(i) * normal.x
        let y_start = float(y1) - float(i) * normal.y
        let x_finish = float(x2) - float(i) * normal.x
        let y_finish = float(y2) - float(i) * normal.y
        var color = float3(0, 0, 0)
        if i < line_quart_width
            color = lerp(tunel_edge_center_vec, base_color, float(i) / float(line_quart_width))
        else
            color = lerp(base_color, backgroud_color_vec, float(i - line_quart_width) / float(line_quart_width))
        graphics::line(x_start, y_start, x_finish, y_finish, vec_to_color(color) | 0x8f000000)


def draw_edge(start, finish, color)
    var to_finish = finish - camera_pos
    var to_start = start - camera_pos

    var finish_z = dot(center_view, to_finish)
    var start_z = dot(center_view, to_start)
    if finish_z <= 1e-5 && start_z <= 1e-5
        return

    let dir = normalize(to_finish - to_start)
    if abs(dot(dir, center_view)) > 0.0001
        if start_z <= 1e-5
            let t1 = max(-dot(to_start, center_view) / dot(dir, center_view), 0.0) + 1e-3
            to_start = to_start + t1 * dir
            start_z = dot(center_view, to_start)

        if finish_z <= 1e-5
            let t2 = max(dot(to_finish, center_view) / dot(dir, center_view), 0.0) + 1e-3
            to_finish = to_finish - t2 * dir
            finish_z = dot(center_view, to_finish)

    let finish_projected_pos = project_shifted(to_finish)
    let start_projected_pos = project_shifted(to_start)

    var width = 8
    if min(start_z, finish_z) > 10.0
        width = 7
    if min(start_z, finish_z) > 20.0
        width = 5
    if min(start_z, finish_z) > 30.0
        width = 3
    draw_line(start_projected_pos.x, start_projected_pos.y, finish_projected_pos.x, finish_projected_pos.y, width, color)

def get_ball_z(pos)
    return dot(center_view, pos - camera_pos)

def draw_ball_shadow(pos)
    var to_center = pos - camera_pos

    var z = get_ball_z(pos)
    if z <= 1e-5
        return

    var top = to_center - center_view * ball_radius * 0.5 + up * sqrt(3.0) * 0.5 * ball_radius
    var top_z = dot(center_view, top)
    top /= top_z
    let projected_top = project_point(pos + up * ball_radius * 1.1).y

    let projected_pos = project_point(pos)

    let radius = projected_pos.y - projected_top
    if shadow_scale * radius < 1.0
        return

    graphics::enable_alpha_blend()
    let alpha = min(uint(255.0 * max(shadow_scale, 0.0) * 0.8), 255u)
    graphics::fill_circle(projected_pos.x, projected_pos.y + 60.0, radius * shadow_scale, 0x000A0A0Au | (alpha << 24u))
    graphics::disable_alpha_blend()


def draw_ball(pos)
    var to_center = pos - camera_pos

    var z = get_ball_z(pos)
    if z <= 1e-5
        return

    var top = to_center +  up * ball_radius * 1.5 //- center_view * ball_radius * 0.5 + up * sqrt(3.0) * 0.5 * ball_radius
    var top_z = dot(center_view, top)
    top /= top_z
    let projected_top = project_point(pos + up * ball_radius * 1.1).y

    to_center /= z
    let projected_pos = project_point(pos)

    let radius = projected_pos.y - projected_top
    graphics::fill_circle(projected_pos.x, projected_pos.y, radius, ball_color)

    to_center = pos - camera_pos
    let trace_radius = radius * 1.5
    // for x in range(projected_pos.x - trace_radius, projected_pos.x + trace_radius)
    //     for y in range(projected_pos.y - trace_radius, projected_pos.y + trace_radius)
    //         // if pow(float(x) - projected_pos.x, 2.0) + pow(float(y) - projected_pos.y, 2.0) > trace_radius * trace_radius
    //         //     continue

    //         let frag_pos = (
    //             float2(x, y) / float(get_screen_height()) * 2.0
    //             - float2(float(get_screen_width()) / float(get_screen_height()), 1.0)
    //         ) * float2(1, -1)
    //         var trace_dir = normalize(center_view * sqrt(1.0 - dot(frag_pos, frag_pos)) + frag_pos.x * right + frag_pos.y * up)
    //         trace_dir = normalize(unproj_dir(float2(x, y)))
    //         let b = -2.0 * dot(trace_dir, to_center)
    //         let c = dot(to_center, to_center) - ball_radius * ball_radius
    //         let D = b * b - 4.0 * c
    //         if D < 0.0
    //             continue
    //         let t = (-b - sqrt(D)) * 0.5
    //         let hit = camera_pos + trace_dir * t
    //         let normal = normalize(hit - pos)
    //         let light = dot(normal, normalize(float3(1, -1, 0)))
    //         graphics::set_pixel(x, y, vec_to_color(normal * 0.5 + float3(0.5)))


def draw_segment(idx)
    let rel_idx = (idx + current_segment + 1) % segments_count
    for i in range(sectors_count)
        draw_edge(segments_edge_points[rel_idx][i], segments_edge_points[(rel_idx + segments_count - 1) % segments_count][i])
        draw_edge(segments_edge_points[rel_idx][i], segments_edge_points[rel_idx][(i + 1) % sectors_count])

def draw_flat_convex(points, color, colors)
    let to_point <- [{ for point in points; point - camera_pos }]
    let z_values <- [{ for vec in to_point; dot(vec, center_view) }]
    if all([{ for z in z_values; z < 1e-5 }])
        return

    var z_corrected_points: array<float3>
    var z_corrected_colors: array<uint>

    let segments = points |> length()
    for i in range(segments)
        let prev_idx = (i + segments - 1) % segments
        let next_idx = (i + 1) % segments
        if z_values[i] > 1e-5
            z_corrected_points |> push(points[i])
            z_corrected_colors |> push(colors[i])
            continue

        if z_values[prev_idx] > 1e-5
            let dir = normalize(points[prev_idx] - points[i])
            let t = max(-dot(to_point[i], center_view) / dot(dir, center_view), 0.0) + 1e-3
            z_corrected_points |> push(points[i] + t * dir)
            z_corrected_colors |> push(colors[i])

        if z_values[next_idx] > 1e-5
            let dir = normalize(points[next_idx] - points[i])
            let t = max(-dot(to_point[i], center_view) / dot(dir, center_view), 0.0) + 1e-3
            z_corrected_points |> push(points[i] + t * dir)
            z_corrected_colors |> push(colors[i])

    var center = float3(0, 0, 0)
    var center_color = float3(0, 0, 0)
    for point, col in z_corrected_points, z_corrected_colors
        center += point
        center_color += color_to_vec(col)
    center_color /= float(length(z_corrected_points))
    center /= float(length(z_corrected_points))
    for i in range(length(z_corrected_points))
        let tri_colors <- [{ uint[3] z_corrected_colors[i];
            z_corrected_colors[(i + 1) % length(z_corrected_colors)];
            vec_to_color(center_color) }]
        let projected_pos <- [{ float2[3] project_point(z_corrected_points[i]);
            project_point(z_corrected_points[(i + 1) % length(z_corrected_points)]);
            project_point(center) }]
        stub_texture |> graphics::draw_triangle_strip(projected_pos, projected_pos, tri_colors)

    // let projected_pos <- [{for point in z_corrected_points; project_point(point)}]
    // graphics::fill_convex_polygon(projected_pos, color)
    // stub_texture |> graphics::draw_triangle_strip(projected_pos, projected_pos, color)

def draw_in_game_crystal(segment_id, sector_idx)
    let cell_center = (
        segments_edge_points[segment_id][sector_idx]
        + segments_edge_points[segment_id][(sector_idx + 1) % sectors_count]
        + segments_edge_points[(segment_id + 1) % segments_count][(sector_idx + 1) % sectors_count]
        + segments_edge_points[(segment_id + 1) % segments_count][sector_idx]
    ) * 0.25
    let seg_normal = normalize(cross(
        segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx],
        + segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]
    ))
    let crystal_center = get_crystal_center(segment_id, sector_idx)

    draw_crystal(crystal_center, float3(1, 0, 0), float3(0, 1, 0), (segment_id + segments_count - 1) % segments_count)

def draw_crystal(crystal_center, right, up, segment_id)
    var points : array<float3>

    let normal = -cross(right, up)
    let crystal_color = float3(0.9)//float3(0.780392f,0.286275f,0.286275f)
    var lighting: array<uint>
    let segments = 6
    for i in range(segments)
        let angle = float(i) / float(segments) * math::PI * 2.0
        let x = (cos(angle) * crystal_scale)
        let y = (sin(angle) * crystal_scale)
        let position = x * right + y * up + crystal_center
        points |> push(position)
        let point_normal = normalize(normal + normalize(x * right + y * up))

        var point_lighting = float3(0.3)
        if segment_id >= 0
            for i in range(sectors_count)
                point_lighting += pow(max(0.0, dot(point_normal, normalize(segments_edge_points[segment_id][i] - position))), 2.0) * tunel_edge_color_vec * 0.3
        else
            point_lighting += -point_normal * 0.5 + float3(0.5)
        point_lighting *= crystal_color
        lighting |> push(make_color(pow(point_lighting, float3(2.2))))

    draw_flat_convex(points, 0xFFFFFFFF, lighting)

def draw_wall(segment_id, sector_idx)
    var points : array<float3>
    let seg_normal = normalize(cross(
        segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx],
        segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]
    ))

    points |> push(segments_edge_points[segment_id][sector_idx])
    points |> push(segments_edge_points[segment_id][(sector_idx + 1) % sectors_count])
    points |> push(segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] + seg_normal * wall_height)
    points |> push(segments_edge_points[segment_id][sector_idx] + seg_normal * wall_height)

    var color: array<uint>
    color |> push(backgroud_color)
    color |> push(backgroud_color)
    color |> push(backgroud_color)
    color |> push(backgroud_color)

    draw_flat_convex(points, backgroud_color, color)

    for i in range(points|>length())
        draw_edge(points[i], points[(i + 1) % points |> length()], tunel_edge_color_vec)

def get_panel_center(segment_id, sector_idx)
    let x = segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx]
    let y = segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]
    return segments_edge_points[segment_id][sector_idx] + x * 0.5 + y * 0.5

def draw_accel_panel(segment_id, sector_idx)
    let x = segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx]
    let y = segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]

    for i in range(3)
        let center = segments_edge_points[segment_id][sector_idx] + x * 0.5 + y / 5.0 * float(i + 2)
        draw_edge(center, center - x * 0.25 - y / 5.0, color_to_vec(fast_tunel_edge_color))
        draw_edge(center, center + x * 0.25 - y / 5.0, color_to_vec(fast_tunel_edge_color))

def draw_deaccel_panel(segment_id, sector_idx)
    let x = segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx]
    let y = segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]

    for i in range(3)
        let center = segments_edge_points[segment_id][sector_idx] + x * 0.5 + y / 5.0 * float(i + 1)
        draw_edge(center, center - x * 0.25 + y / 5.0, color_to_vec(slow_tunel_edge_color))
        draw_edge(center, center + x * 0.25 + y / 5.0, color_to_vec(slow_tunel_edge_color))

def draw_ui
    set_font_size(15)
    text_out(100, 30, "{gathered_crystals} of {crystals_to_win} crystals gathered", 0xFFFFFF)

def draw_post_mortem_ui
    let text = "If he dies, he dies."
    set_font_size(50)
    var text_size = get_text_size(text)
    text_out(get_screen_width() / 2 - int(text_size.x) / 2, get_screen_height() / 2 - int(text_size.y) / 2 - 100, text, 0xFFFFFF)
    let counter = "Try again in {int(seconds_to_restart)} seconds"
    text_size = get_text_size(counter)
    text_out(get_screen_width() / 2 - int(text_size.x) / 2, get_screen_height() / 2 - int(text_size.y) / 2, counter, 0xFFFFFF)

def draw_layer(idx, no_objects, no_tunel)
    if !no_tunel
        for i in range(sectors_count)
            draw_edge(segments_edge_points[idx][i], segments_edge_points[(idx + segments_count - 1) % segments_count][i], tunel_edge_color_vec)
            draw_edge(segments_edge_points[idx][i], segments_edge_points[idx][(i + 1) % sectors_count], tunel_edge_color_vec)
        for panel in fast_panels
            if panel.x == idx
                draw_accel_panel(panel.x, panel.y)
        for panel in slow_panels
            if panel.x == idx
                draw_deaccel_panel(panel.x, panel.y)
    if no_objects
        return
    for crystal in crystals
        if crystal.x == idx
            draw_in_game_crystal(crystal.x, crystal.y)
    for wall in walls
        if wall.x == idx
            draw_wall(wall.x, wall.y)

def draw_arrow(from, to)
    graphics::line(from.x, from.y, to.x, to.y, 0xCC0000)
    let norm = normalize(float2(to.y - from.y, from.x - to.x))
    let back_dir = normalize(from - to)
    let width = 3.0
    let side1 = normalize(norm + width * back_dir) * 7.0 + to
    let side2 = normalize(-norm + width * back_dir) * 7.0 + to
    graphics::line(to.x, to.y, side1.x, side1.y, 0xCC0000)
    graphics::line(to.x, to.y, side2.x, side2.y, 0xCC0000)

def draw_cut_scene
    for i in range(segments_count - 2)
        draw_layer((segments_count - 3 - i + current_segment + 1) % segments_count, i >= segments_count - 4, false)
    if run_engine
        let actors = clamp(gathered_crystals, 4, 16)
        for i in range(actors)
            let angle = float(i) / float(actors) * math::PI * 2.0
            let timing = show_names ? names_timing : (cut_scene_time > names_timing ? cut_scene_time - names_display_duration : cut_scene_time)
            let t = timing - run_engine_timing + math::PI
            let scale = 5.0
            let x = scale * (cos(t) - pow(sin(t), 2.0) / sqrt(2.0) + 1.0)
            let y = scale * cos(t) * sin(t)
            let rot_x = cos(angle) * x - sin(angle) * y
            let rot_y = sin(angle) * x + cos(angle) * y
            draw_crystal(ball_pos + right * rot_x + up * rot_y + normalize(ball_pos - camera_pos) * 3.0, right, up, -1)
    draw_ball(ball_pos)
    if show_names
        text_out(600, 250, "You", 0xCC0000)
        draw_arrow(float2(600, 265), float2(570, 275))
        text_out(650, 150, "Your star crystals", 0xCC0000)
        draw_arrow(float2(647, 160), float2(622, 170))

    if show_thanks
        let text = "Thank you for playing!"
        set_font_size(50)
        let text_size = get_text_size(text)
        text_out(get_screen_width() / 2 - int(text_size.x) / 2, get_screen_height() / 2 - int(text_size.y) / 2 - 100, text, 0xFFFFFF)

def draw_fog
    let center = segments_control_points[(segments_count - 3 - start_segment + current_segment + 1) % segments_count]
    var to_point = center - camera_pos
    var z = dot(center_view, to_point)

    to_point /= z
    let projected_pos = float2(
        (dot(to_point, right) + float(get_screen_width()) / float(get_screen_height())) * 0.5 * float(get_screen_height()),
        (-dot(to_point, up) + 1.0) * 0.5 * float(get_screen_height()))
    graphics::enable_alpha_blend()
    draw_image(far_fog, int(projected_pos.x) - 50, int(projected_pos.y) - 50)
    graphics::disable_alpha_blend()

// this function will be called every frame after 'act',
// you can draw anything in this function
[export]
def draw
    if cut_scene
        draw_cut_scene()
        return

    graphics::fill_rect(0, 0, get_screen_width(), get_screen_height(), backgroud_color)
    draw_fog()
    for i in range(start_segment, segments_count - 2)
        draw_layer((segments_count - 3 - i + current_segment + 1) % segments_count, i >= segments_count - 4, false)
    draw_ball_shadow(shadow_pos)
    draw_ball(ball_pos)
    for i in range(segments_count - 4, segments_count - 2)
        draw_layer((segments_count - 3 - i + current_segment + 1) % segments_count, false, true)

    if restart
        draw_post_mortem_ui()
    else
        draw_ui()
    return
