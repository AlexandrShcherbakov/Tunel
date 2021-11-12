require daslib/media
require daslib/functional
require daslib/algorithm
options debugger            // uncomment for debug in VS Code
require daslib/debug        // uncomment for debug in VS Code

var
    tunel_edge_color_vec: float3
    tunel_edge_center_vec: float3
    backgroud_color_vec: float3
    tunel_edge_color = 0x4B4BCE
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

let
    segment_width = 1.0
    segments_count = 30
    sectors_count = 15
    tunel_edge_center = 0xE0E0E0
    backgroud_color = 0x2B2B30
    lowest_move_speed = 4.0
    crystal_scale = 0.25
    crystals_to_win = 1
    wall_height = 0.5
    restart_timeout = 5.0

def reset
    ball_radius = 0.15 //60.0
    camera_pos = float3(0.0, 0.0, 0.0)
    center_view = float3(0, 0, 1)
    up = float3(0, 1, 0)
    right = float3(1, 0, 0)
    current_segment = 0
    one_segment_point_back = generate_point(-1.0)
    slice_ball_pos = float2(0, 0)
    slice_ball_vel = float2(0, 0)
    move_speed = lowest_move_speed
    shadow_scale = 0.9
    current_time = 0.0
    seed = int4(762, 22, 3, 4)
    crystals |> clear()
    walls |> clear()
    gathered_crystals = 0
    win = false
    start_segment = 0

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

// 'initialize' runs once when game starts and every hot-reload
[export]
def initialize
    tunel_edge_color_vec = color_to_vec(tunel_edge_color)
    tunel_edge_center_vec = color_to_vec(tunel_edge_center)
    backgroud_color_vec = color_to_vec(backgroud_color)

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


// this function is called to update game data,
// dt - time elapsed since the previous update (in seconds)
[export]
def act(dt: float)
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

    if get_key(VK_RIGHT)
        slice_ball_vel.x += 4.0 * dt
    if get_key(VK_LEFT)
        slice_ball_vel.x -= 4.0 * dt
    if get_key(VK_UP)
        move_speed = min(move_speed + 4.0 * dt, 8.0)
    if get_key(VK_DOWN)
        move_speed = max(move_speed - 4.0 * dt, lowest_move_speed)

    move_speed = max(move_speed * 0.999, lowest_move_speed)

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
        let radius = ball_radius + wall_height * 0.5
        if length(wall_center - ball_pos) < radius
            restart = true
            seconds_to_restart = restart_timeout

    let new_segment = int(camera_pos.z)
    if new_segment != current_segment
        if win
            start_segment++
        else
            let rounded_idx = current_segment % segments_count
            let rounded_prev_idx = (current_segment + segments_count - 1) % segments_count
            one_segment_point_back = segments_control_points[rounded_idx]
            segments_control_points[rounded_idx] = generate_point(float(current_segment + segments_count))
            segments_edge_points[rounded_prev_idx] <- generate_edge_points(segments_control_points[rounded_prev_idx], segments_control_points[rounded_idx])

            let rand_value = random::random_int(seed) % 5
            if rand_value == 0
                crystals |> push(int2(
                    (rounded_prev_idx + segments_count - 1) % segments_count,
                    random::random_int(seed) % ((sectors_count - 1) / 2) + sectors_count / 2
                ))
            if rand_value == 1
                walls |> push(int2(
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

    current_segment = new_segment

    return


def draw_line(var x1, y1, x2, y2, width)
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
            color = lerp(tunel_edge_center_vec, tunel_edge_color_vec, float(i) / float(line_quart_width))
        else
            color = lerp(tunel_edge_color_vec, backgroud_color_vec, float(i - line_quart_width) / float(line_quart_width))
        graphics::line(x_start, y_start, x_finish, y_finish, vec_to_color(color) | 0x8f000000)

    for i in range(line_half_width)
        let x_start = float(x1) - float(i) * normal.x
        let y_start = float(y1) - float(i) * normal.y
        let x_finish = float(x2) - float(i) * normal.x
        let y_finish = float(y2) - float(i) * normal.y
        var color = float3(0, 0, 0)
        if i < line_quart_width
            color = lerp(tunel_edge_center_vec, tunel_edge_color_vec, float(i) / float(line_quart_width))
        else
            color = lerp(tunel_edge_color_vec, backgroud_color_vec, float(i - line_quart_width) / float(line_quart_width))
        graphics::line(x_start, y_start, x_finish, y_finish, vec_to_color(color) | 0x8f000000)


def draw_edge(start, finish)
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

    to_finish /= finish_z
    let finish_projected_pos = float2(
        (dot(to_finish, right) + float(get_screen_width()) / float(get_screen_height())) * 0.5 * float(get_screen_height()),
        (-dot(to_finish, up) + 1.0) * 0.5 * float(get_screen_height()))

    to_start /= start_z
    let start_projected_pos = float2(
        (dot(to_start, right) + float(get_screen_width()) / float(get_screen_height())) * 0.5 * float(get_screen_height()),
        (-dot(to_start, up) + 1.0) * 0.5 * float(get_screen_height()))

    var width = 8
    if min(start_z, finish_z) > 10.0
        width = 7
    if min(start_z, finish_z) > 20.0
        width = 5
    if min(start_z, finish_z) > 30.0
        width = 3
    draw_line(start_projected_pos.x, start_projected_pos.y, finish_projected_pos.x, finish_projected_pos.y, width)

def get_ball_z(pos)
    return dot(center_view, pos - camera_pos)

def draw_ball_shadow(pos)
    var to_center = pos - camera_pos

    var z = get_ball_z(pos)
    if z <= 1e-5
        return

    to_center /= z
    let projected_pos = float2(
        (dot(to_center, right) + float(get_screen_width()) / float(get_screen_height())) * 0.5 * float(get_screen_height()),
        (-dot(to_center, up) + 1.0) * 0.5 * float(get_screen_height()))

    var top = to_center - center_view * ball_radius * 0.5 + up * sqrt(3.0) * 0.5 * ball_radius
    var top_z = dot(center_view, top)
    top /= top_z
    let projected_top = (-dot(top, up) + 1.0) * 0.5 * float(get_screen_height())

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

    to_center /= z
    let projected_pos = float2(
        (dot(to_center, right) + float(get_screen_width()) / float(get_screen_height())) * 0.5 * float(get_screen_height()),
        (-dot(to_center, up) + 1.0) * 0.5 * float(get_screen_height()))

    var top = to_center - center_view * ball_radius * 0.5 + up * sqrt(3.0) * 0.5 * ball_radius
    var top_z = dot(center_view, top)
    top /= top_z
    let projected_top = (-dot(top, up) + 1.0) * 0.5 * float(get_screen_height())

    let radius = projected_pos.y - projected_top
    graphics::fill_circle(projected_pos.x, projected_pos.y, radius, ball_color)

    // for x in range(projected_pos.x - radius, projected_pos.x + radius)
    //     for y in range(projected_pos.y - radius, projected_pos.y + radius)
    //         if pow(float(x) - projected_pos.x, 2.0) + pow(float(y) - projected_pos.y, 2.0) > radius * radius
    //             continue

    //         let frag_pos = float2(x, y) / float2(get_screen_width(), get_screen_height()) - float2(0.5)
    //         let trace_dir = normalize(center_view + frag_pos.x * right + frag_pos.y * up)
    //         let b = -2.0 * dot(trace_dir, to_center)
    //         let c = ball_radius * ball_radius - dot(to_center, to_center)
    //         let D = b * b - 4.0 * c
    //         if D < 0.0
    //             continue
    //         let t = (-b + sqrt(D)) * 0.5
    //         let hit = camera_pos + trace_dir * t
    //         let normal = normalize(hit - pos)
    //         let light = dot(normal, normalize(float3(1, -1, 0)))
    //         graphics::set_pixel(x, y, vec_to_color(normal * 0.5 + float3(0.5)))


def draw_segment(idx)
    let rel_idx = (idx + current_segment + 1) % segments_count
    for i in range(sectors_count)
        draw_edge(segments_edge_points[rel_idx][i], segments_edge_points[(rel_idx + segments_count - 1) % segments_count][i])
        draw_edge(segments_edge_points[rel_idx][i], segments_edge_points[rel_idx][(i + 1) % sectors_count])

def draw_flat_convex(points, color)
    let to_point <- [{ for point in points; point - camera_pos }]
    let z_values <- [{ for vec in to_point; dot(vec, center_view) }]
    if all([{ for z in z_values; z < 1e-5 }])
        return

    var z_corrected_points: array<float3>

    let segments = points |> length()
    for i in range(segments)
        let prev_idx = (i + segments - 1) % segments
        let next_idx = (i + 1) % segments
        if z_values[i] > 1e-5
            z_corrected_points |> push(points[i])
            continue

        if z_values[prev_idx] > 1e-5
            let dir = normalize(points[prev_idx] - points[i])
            let t = max(-dot(to_point[i], center_view) / dot(dir, center_view), 0.0) + 1e-3
            z_corrected_points |> push(points[i] + t * dir)

        if z_values[next_idx] > 1e-5
            let dir = normalize(points[next_idx] - points[i])
            let t = max(-dot(to_point[i], center_view) / dot(dir, center_view), 0.0) + 1e-3
            z_corrected_points |> push(points[i] + t * dir)

    var z_corrected_to_points <- [{ for point in z_corrected_points; point - camera_pos }]
    let corrected_z <- [{ for vec in z_corrected_to_points; dot(vec, center_view) }]
    z_corrected_to_points <- [{ for point, z in z_corrected_to_points, corrected_z; point / z }]
    let projected_pos <- [{for to_center in z_corrected_to_points; float2(
        (dot(to_center, right) + float(get_screen_width()) / float(get_screen_height())) * 0.5 * float(get_screen_height()),
        (-dot(to_center, up) + 1.0) * 0.5 * float(get_screen_height())
    )}]

    graphics::fill_convex_polygon(projected_pos, color)

def draw_crystal(segment_id, sector_idx)
    var points : array<float3>
    let segments = 6
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

    for i in range(segments)
        let angle = float(i) / float(segments) * math::PI * 2.0
        let x = (cos(angle) * crystal_scale)
        let y = (sin(angle) * crystal_scale)
        points |> push(float3(x, y, 0.0) + crystal_center)

    draw_flat_convex(points, 0xC77509)

def draw_wall(segment_id, sector_idx)
    var points : array<float3>
    let seg_normal = normalize(cross(
        segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] - segments_edge_points[segment_id][sector_idx],
        + segments_edge_points[(segment_id + 1) % segments_count][sector_idx] - segments_edge_points[segment_id][sector_idx]
    ))

    points |> push(segments_edge_points[segment_id][sector_idx])
    points |> push(segments_edge_points[segment_id][(sector_idx + 1) % sectors_count])
    points |> push(segments_edge_points[segment_id][(sector_idx + 1) % sectors_count] + seg_normal * wall_height)
    points |> push(segments_edge_points[segment_id][sector_idx] + seg_normal * wall_height)

    draw_flat_convex(points, backgroud_color)

    for i in range(points|>length())
        draw_edge(points[i], points[(i + 1) % points |> length()])

def draw_ui
    set_font_size(15)
    text_out(100, 30, "{gathered_crystals} of {crystals_to_win} crystals gathered", 0xFFFFFF)

def draw_post_mortem_ui
    let text = "If he dies, he dies."
    set_font_size(50)
    let text_size = get_text_size(text)
    text_out(get_screen_width() / 2 - int(text_size.x) / 2, get_screen_height() / 2 - int(text_size.y) / 2 - 100, text, 0xFFFFFF)
    let counter = "Try again in {int(seconds_to_restart)} seconds"
    text_out(get_screen_width() / 2 - int(text_size.x) / 2, get_screen_height() / 2 - int(text_size.y) / 2, counter, 0xFFFFFF)

def draw_layer(idx, no_objects, no_tunel)
    if !no_tunel
        for i in range(sectors_count)
            draw_edge(segments_edge_points[idx][i], segments_edge_points[(idx + segments_count - 1) % segments_count][i])
            draw_edge(segments_edge_points[idx][i], segments_edge_points[idx][(i + 1) % sectors_count])
    if no_objects
        return
    for crystal in crystals
        if crystal.x == idx
            draw_crystal(crystal.x, crystal.y)
    for wall in walls
        if wall.x == idx
            draw_wall(wall.x, wall.y)

// this function will be called every frame after 'act',
// you can draw anything in this function
[export]
def draw
    graphics::fill_rect(0, 0, get_screen_width(), get_screen_height(), backgroud_color)
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
