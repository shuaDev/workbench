package workbench

using import "core:math"
      import "gpu"
      import wbm "math"

do_camera_movement :: proc(camera: ^gpu.Camera, speed: f32) {
    up      := Vec3{0,  1,  0};
    down    := Vec3{0, -1,  0};
    forward := wbm.quaternion_forward(current_camera.rotation);
	right   := wbm.quaternion_right(current_camera.rotation);

    back := -forward;
    left := -right;

	if get_input(.E) { current_camera.position += up      * speed * fixed_delta_time; }
	if get_input(.Q) { current_camera.position += down    * speed * fixed_delta_time; }
	if get_input(.W) { current_camera.position += forward * speed * fixed_delta_time; }
	if get_input(.S) { current_camera.position += back    * speed * fixed_delta_time; }
	if get_input(.A) { current_camera.position += left    * speed * fixed_delta_time; }
	if get_input(.D) { current_camera.position += right   * speed * fixed_delta_time; }

	if get_input(.Mouse_Right) {
		SENSITIVITY :: 0.1;
		delta := cursor_screen_position_delta;
		delta *= SENSITIVITY;
		degrees := Vec3{delta.y, -delta.x, cursor_scroll};
		current_camera.rotation = rotate_quat_by_degrees(current_camera.rotation, degrees);
	}
}

rotate_quat_by_degrees :: proc(q: Quat, degrees: Vec3) -> Quat {
	x := axis_angle(Vec3{1, 0, 0}, to_radians(degrees.x));
	y := axis_angle(Vec3{0, 1, 0}, to_radians(degrees.y));
	z := axis_angle(Vec3{0, 0, 1}, to_radians(degrees.z));
	result := mul(y, q);
	result  = mul(result, x);
	result  = mul(result, z);
	return quat_norm(result);
}