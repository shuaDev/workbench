package workbench

using import          "core:fmt"
      import          "core:sort"
      import          "core:strings"
      import          "core:mem"
      import rt       "core:runtime"
      import          "core:os"

      import          "platform"
      import          "gpu"
using import          "math"
using import          "types"
using import          "logging"
using import          "basic"

      import          "external/stb"
      import          "external/glfw"
      import          "external/imgui"

/*

--- Cameras
{
	init_camera                 :: proc(camera: ^Camera, is_perspective: bool, size: f32, pixel_width, pixel_height: int, make_framebuffer := false)
	delete_camera               :: proc(camera: Camera)
	PUSH_CAMERA                 :: proc(camera: ^Camera) -> ^Camera
	push_camera_non_deferred    :: proc(camera: ^Camera) -> ^Camera
	pop_camera                  :: proc(old_camera: ^Camera)
	camera_prerender            :: proc(camera: ^Camera)
	update_camera_pixel_size    :: proc(using camera: ^Camera, new_width: f32, new_height: f32)
	construct_view_matrix       :: proc(camera: ^Camera) -> Mat4
	construct_projection_matrix :: proc(camera: ^Camera) -> Mat4
	construct_rendermode_matrix :: proc(camera: ^Camera) -> Mat4
}

--- Textures
{
	create_texture        :: proc(w, h: int, gpu_format: gpu.Internal_Color_Format, pixel_format: gpu.Pixel_Data_Format, element_type: gpu.Texture2D_Data_Type, initial_data: ^u8 = nil, texture_target := gpu.Texture_Target.Texture2D) -> Texture
	delete_texture        :: proc(texture: Texture)
	draw_texture          :: proc(texture: Texture, pixel1: Vec2, pixel2: Vec2, color := Colorf{1, 1, 1, 1})
	write_texture_to_file :: proc(filepath: string, texture: Texture)
}

--- Framebuffers
{
	default_framebuffer_settings :: proc() -> Framebuffer_Settings
	create_color_framebuffer     :: proc(width, height: int) -> Framebuffer
	create_depth_framebuffer     :: proc(width, height: int) -> Framebuffer
	delete_framebuffer           :: proc(framebuffer: Framebuffer)
	bind_framebuffer             :: proc(framebuffer: ^Framebuffer)
	unbind_framebuffer           :: proc()
}

--- Models
{
	add_mesh_to_model      :: proc(model: ^Model, vertices: []$Vertex_Type, indices: []u32) -> int
	remove_mesh_from_model :: proc(model: ^Model, idx: int)
	update_mesh            :: proc(model: ^Model, idx: int, vertices: []$Vertex_Type, indices: []u32)
	delete_model           :: proc(model: Model)
	draw_model             :: proc(model: Model, position: Vec3, scale: Vec3, rotation: Quat, texture: Texture, color: Colorf, depth_test: bool)
}

--- Rendermodes
{
	rendermode_world :: proc()
	rendermode_unit  :: proc()
	rendermode_pixel :: proc()
}

--- Helpers
{
	create_cube_model :: proc() -> Model
	create_quad_model :: proc() -> Model

	get_mouse_world_position        :: proc(camera: ^Camera, cursor_unit_position: Vec2) -> Vec3
	get_mouse_direction_from_camera :: proc(camera: ^Camera, cursor_unit_position: Vec2) -> Vec3

	world_to_viewport :: proc(position: Vec3, camera: ^Camera) -> Vec3
	world_to_pixel    :: proc(a: Vec3, camera: ^Camera, pixel_width: f32, pixel_height: f32) -> Vec3
	world_to_unit     :: proc(a: Vec3, camera: ^Camera) -> Vec3

	unit_to_pixel    :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3
	unit_to_viewport :: proc(a: Vec3) -> Vec3

	pixel_to_viewport :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3
	pixel_to_unit     :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3

	viewport_to_pixel :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3
	viewport_to_unit  :: proc(a: Vec3) -> Vec3
}

*/


//
// Camera
//

Camera :: struct {
    is_perspective: bool,

    // orthographic -> size in world units from center of screen to top of screen
    // perspective  -> fov
    size: f32,

    near_plane: f32,
    far_plane:  f32,

    clear_color: Colorf,

    current_rendermode: Rendermode,

    position: Vec3,
    rotation: Quat,

    pixel_width: f32,
    pixel_height: f32,
    aspect: f32,

    draw_mode: gpu.Draw_Mode,

    framebuffer: Framebuffer,
}

init_camera :: proc(camera: ^Camera, is_perspective: bool, size: f32, pixel_width, pixel_height: int, make_framebuffer := false) {
    camera.is_perspective = is_perspective;
    camera.size = size;
    camera.near_plane = 0.01;
    camera.far_plane = 1000;
    camera.position = Vec3{};
    camera.rotation = Quat{0, 0, 0, 1};
    camera.draw_mode = .Triangles;
    camera.clear_color = {1, 0, 1, 1};
    camera.pixel_width = cast(f32)pixel_width;
    camera.pixel_height = cast(f32)pixel_height;
    camera.aspect = camera.pixel_width / camera.pixel_height;

    assert(camera.framebuffer.fbo == 0);

    if make_framebuffer {
        assert(pixel_width > 0);
        assert(pixel_height > 0);
        camera.framebuffer = create_color_framebuffer(pixel_width, pixel_height);
    }
}

delete_camera :: proc(camera: Camera) {
    if camera.framebuffer.fbo != 0 {
        delete_framebuffer(camera.framebuffer);
    }
}

@(deferred_out=pop_camera)
PUSH_CAMERA :: proc(camera: ^Camera) -> ^Camera {
	return push_camera_non_deferred(camera);
}

push_camera_non_deferred :: proc(camera: ^Camera) -> ^Camera {
	old_camera := current_camera;
	current_camera = camera;

	camera_prerender(camera);

	return old_camera;
}

pop_camera :: proc(old_camera: ^Camera) {
	current_camera = old_camera;

	gpu.viewport(0, 0, cast(int)current_camera.pixel_width, cast(int)current_camera.pixel_height);
	if current_camera.framebuffer.fbo != 0 {
		bind_framebuffer(&current_camera.framebuffer);
	}
	else {
		unbind_framebuffer();
	}
}

camera_prerender :: proc(camera: ^Camera) {
	gpu.enable(gpu.Capabilities.Blend);
	gpu.blend_func(.Src_Alpha, .One_Minus_Src_Alpha);
	gpu.viewport(0, 0, cast(int)camera.pixel_width, cast(int)camera.pixel_height);

	if camera.framebuffer.fbo != 0 {
		bind_framebuffer(&camera.framebuffer);
	}
	else {
		unbind_framebuffer();
	}

	gpu.set_clear_color(camera.clear_color);
	gpu.clear_screen(.Color_Buffer | .Depth_Buffer);
}

update_camera_pixel_size :: proc(using camera: ^Camera, new_width: f32, new_height: f32) {
    pixel_width = new_width;
    pixel_height = new_height;
    aspect = new_width / new_height;

    if framebuffer.fbo != 0 {
        if framebuffer.width != cast(int)new_width || framebuffer.height != cast(int)new_height {
            logln("Rebuilding framebuffer...");
            delete_framebuffer(framebuffer);
            framebuffer = create_color_framebuffer(cast(int)new_width, cast(int)new_height);
        }
    }
}

// todo(josh): it's probably slow that we dont cache matrices at all :grimacing:
construct_view_matrix :: proc(camera: ^Camera) -> Mat4 {
	view_matrix := translate(identity(Mat4), -camera.position);

	rotation := camera.rotation;
	if camera.current_rendermode != .World {
		rotation = {0, 0, 0, 1};
	}
    rotation_matrix := quat_to_mat4(inverse(rotation));
    view_matrix = mul(rotation_matrix, view_matrix);
    return view_matrix;
}

construct_projection_matrix :: proc(camera: ^Camera) -> Mat4 {
    if camera.is_perspective {
        return perspective(to_radians(camera.size), camera.aspect, camera.near_plane, camera.far_plane);
    }
    else {
        top    : f32 =  1 * camera.size;
        bottom : f32 = -1 * camera.size;
        left   : f32 = -1 * camera.aspect * camera.size;
        right  : f32 =  1 * camera.aspect * camera.size;
        return ortho3d(left, right, bottom, top, camera.near_plane, camera.far_plane);
    }
}

construct_rendermode_matrix :: proc(camera: ^Camera) -> Mat4 {
    #complete
    switch camera.current_rendermode {
        case .World: {
            return construct_projection_matrix(camera);
        }
        case .Unit: {
            unit := translate(identity(Mat4), Vec3{-1, -1, 0});
            unit = scale(unit, 2);
            return unit;
        }
        case .Pixel: {
            pixel := scale(identity(Mat4), Vec3{1.0 / camera.pixel_width, 1.0 / camera.pixel_height, 0});
            pixel = scale(pixel, 2);
            pixel = translate(pixel, Vec3{-1, -1, 0});
            return pixel;
        }
        case: panic(tprint(camera.current_rendermode));
    }

    unreachable();
    return {};
}



//
// Textures
//

Texture :: struct {
    gpu_id: gpu.TextureId,

    width, height: int,

    target: gpu.Texture_Target,
    format: gpu.Pixel_Data_Format,
    element_type: gpu.Texture2D_Data_Type,
}

create_texture :: proc(ww, hh: int, gpu_format: gpu.Internal_Color_Format, pixel_format: gpu.Pixel_Data_Format, element_type: gpu.Texture2D_Data_Type, initial_data: ^u8 = nil) -> Texture {
	texture := gpu.gen_texture();
	gpu.bind_texture2d(texture);

	assert(initial_data != nil);
	gpu.tex_image2d(.Texture2D, 0, gpu_format, cast(i32)ww, cast(i32)hh, 0, pixel_format, element_type, initial_data);
	gpu.tex_parameteri(.Texture2D, .Mag_Filter, .Nearest);
	gpu.tex_parameteri(.Texture2D, .Min_Filter, .Nearest);

	return Texture{texture, ww, hh, .Texture2D, pixel_format, element_type};
}

delete_texture :: proc(texture: Texture) {
	gpu.delete_texture(texture.gpu_id);
}

draw_texture :: proc(texture: Texture, pixel1: Vec2, pixel2: Vec2, color := Colorf{1, 1, 1, 1}) {
	rendermode_pixel();
	center := to_vec3(pixel1 + ((pixel2 - pixel1) / 2));
	size   := to_vec3(pixel2 - pixel1);
	draw_model(wb_quad_model, center, size, {0, 0, 0, 1}, texture, {1, 1, 1, 1}, false);
}

write_texture_to_file :: proc(filepath: string, texture: Texture) {
	assert(texture.target == .Texture2D, "Not sure if this is an error, delete this if it isn't");
	data := make([]u8, 4 * texture.width * texture.height);
	defer delete(data);
	gpu.bind_texture2d(texture.gpu_id);
	gpu.get_tex_image(texture.target, .RGBA, .Unsigned_Byte, &data[0]);
	stb.write_png(filepath, texture.width, texture.height, 4, data, 4 * texture.width);
	gpu.log_errors(#procedure);
}



//
// Framebuffers
//

Framebuffer :: struct {
    fbo: gpu.FBO,
    texture: Texture,
    rbo: gpu.RBO,

    width, height: int,
}

create_color_framebuffer :: proc(width, height: int) -> Framebuffer {
	fbo := gpu.gen_framebuffer();
	gpu.bind_fbo(fbo);

	texture := gpu.gen_texture();
	gpu.bind_texture2d(texture);

	gpu.tex_image2d(.Texture2D, 0, .RGBA, cast(i32)width, cast(i32)height, 0, .RGBA, .Unsigned_Byte, nil);
	gpu.tex_parameteri(.Texture2D, .Mag_Filter, .Nearest);
	gpu.tex_parameteri(.Texture2D, .Min_Filter, .Nearest);
	gpu.tex_parameteri(.Texture2D, .Wrap_S, .Repeat);
	gpu.tex_parameteri(.Texture2D, .Wrap_T, .Repeat);

	gpu.framebuffer_texture2d(.Color0, texture);

	rbo := gpu.gen_renderbuffer();
	gpu.bind_rbo(rbo);

	gpu.renderbuffer_storage(.Depth24_Stencil8, cast(i32)width, cast(i32)height);
	gpu.framebuffer_renderbuffer(.Depth_Stencil, rbo);
	gpu.draw_buffer(cast(u32)gpu.Framebuffer_Attachment.Color0);

	gpu.assert_framebuffer_complete();

	gpu.bind_texture2d(0);
	gpu.bind_rbo(0);
	gpu.bind_fbo(0);

	framebuffer := Framebuffer{fbo, Texture{texture, width, height, .Texture2D, .RGBA, .Unsigned_Byte}, rbo, width, height};
	return framebuffer;
}

create_depth_framebuffer :: proc(width, height: int) -> Framebuffer {
	fbo := gpu.gen_framebuffer();
	gpu.bind_fbo(fbo);

	texture := gpu.gen_texture();
	gpu.bind_texture2d(texture);

	gpu.tex_image2d(.Texture2D, 0, .Depth_Component, cast(i32)width, cast(i32)height, 0, .Depth_Component, .Float, nil);
	gpu.tex_parameteri(.Texture2D, .Mag_Filter, .Nearest);
	gpu.tex_parameteri(.Texture2D, .Min_Filter, .Nearest);
	gpu.tex_parameteri(.Texture2D, .Wrap_S, .Repeat);
	gpu.tex_parameteri(.Texture2D, .Wrap_T, .Repeat);

	gpu.framebuffer_texture2d(.Depth, texture);

	gpu.draw_buffer(0);
	gpu.read_buffer(0);

	gpu.assert_framebuffer_complete();

	gpu.bind_texture2d(0);
	gpu.bind_rbo(0);
	gpu.bind_fbo(0);

	framebuffer := Framebuffer{fbo, Texture{texture, width, height, .Texture2D, .Depth_Component, .Float}, 0, width, height};
	return framebuffer;
}

delete_framebuffer :: proc(framebuffer: Framebuffer) {
	gpu.delete_rbo(framebuffer.rbo);
	delete_texture(framebuffer.texture);
	gpu.delete_fbo(framebuffer.fbo);
}

bind_framebuffer :: proc(framebuffer: ^Framebuffer) {
	gpu.bind_fbo(framebuffer.fbo);
}

unbind_framebuffer :: proc() {
	gpu.bind_fbo(0);
}



//
// Models and Meshes
//

Model :: struct {
	name: string,
    meshes: [dynamic]Mesh,
}

Mesh :: struct {
    vao: gpu.VAO,
    vbo: gpu.VBO,
    ibo: gpu.EBO,
    vertex_type: ^rt.Type_Info,

    index_count:  int,
    vertex_count: int,
}

Vertex2D :: struct {
	position: Vec2,
	tex_coord: Vec2,
	color: Colorf,
}

Vertex3D :: struct {
	position: Vec3,
	tex_coord: Vec3, // todo(josh): should this be a Vec2?
	color: Colorf,
	normal: Vec3,
}

// todo(josh): maybe shouldn't use strings for mesh names, not sure
add_mesh_to_model :: proc(model: ^Model, vertices: []$Vertex_Type, indices: []u32, loc := #caller_location) -> int {
	vao := gpu.gen_vao();
	vbo := gpu.gen_vbo();
	ibo := gpu.gen_ebo();

	idx := len(model.meshes);
	mesh := Mesh{vao, vbo, ibo, type_info_of(Vertex_Type), len(indices), len(vertices)};
	append(&model.meshes, mesh, loc);

	update_mesh(model, idx, vertices, indices);

	return idx;
}

remove_mesh_from_model :: proc(model: ^Model, idx: int, loc := #caller_location) {
	assert(idx < len(model.meshes));
	mesh := model.meshes[idx];
	_internal_delete_mesh(mesh, loc);
	unordered_remove(&model.meshes, idx);
}

update_mesh :: proc(model: ^Model, idx: int, vertices: []$Vertex_Type, indices: []u32) {
	assert(idx < len(model.meshes));
	mesh := &model.meshes[idx];

	gpu.bind_vao(mesh.vao);

	gpu.bind_vbo(mesh.vbo);
	gpu.buffer_vertices(vertices);

	gpu.bind_ibo(mesh.ibo);
	gpu.buffer_elements(indices);

	gpu.bind_vao(0);

	mesh.vertex_type  = type_info_of(Vertex_Type);
	mesh.index_count  = len(indices);
	mesh.vertex_count = len(vertices);
}

delete_model :: proc(model: Model, loc := #caller_location) {
	for mesh in model.meshes {
		_internal_delete_mesh(mesh, loc);
	}
	delete(model.meshes);
}

_internal_delete_mesh :: proc(mesh: Mesh, loc := #caller_location) {
	gpu.delete_vao(mesh.vao);
	gpu.delete_buffer(mesh.vbo);
	gpu.delete_buffer(mesh.ibo);
	gpu.log_errors(#procedure, loc);
}

draw_model :: proc(model: Model, position: Vec3, scale: Vec3, rotation: Quat, texture: Texture, color: Colorf, depth_test: bool, loc := #caller_location) {
	// projection matrix
	projection_matrix := construct_rendermode_matrix(current_camera);

	// view matrix
	view_matrix := construct_view_matrix(current_camera);

	// model_matrix
	model_p := translate(identity(Mat4), position);
	model_s := math.scale(identity(Mat4), scale);
	model_r := quat_to_mat4(rotation);
	model_matrix := mul(mul(model_p, model_r), model_s);

	// shader stuff
	program := gpu.get_current_shader();

	gpu.uniform1i(program, "texture_handle", 0);
	gpu.uniform3f(program, "camera_position", expand_to_tuple(current_camera.position));
	gpu.uniform1i(program, "has_texture", texture.gpu_id != 0 ? 1 : 0);
	gpu.uniform4f(program, "mesh_color", color.r, color.g, color.b, color.a);

	gpu.uniform_matrix4fv(program, "model_matrix",      1, false, &model_matrix[0][0]);
	gpu.uniform_matrix4fv(program, "view_matrix",       1, false, &view_matrix[0][0]);
	gpu.uniform_matrix4fv(program, "projection_matrix", 1, false, &projection_matrix[0][0]);

	if depth_test {
		gpu.enable(.Depth_Test);
	}
	else {
		gpu.disable(.Depth_Test);
	}
	gpu.log_errors(#procedure);

	for mesh in model.meshes {
		gpu.bind_vao(mesh.vao);
		gpu.bind_vbo(mesh.vbo);
		gpu.bind_ibo(mesh.ibo);
		gpu.active_texture0();
		gpu.bind_texture2d(texture.gpu_id); // todo(josh): handle multiple textures per model

		gpu.log_errors(#procedure);

		// todo(josh): I don't think we need this since VAOs store the VertexAttribPointer calls
		gpu.set_vertex_format(mesh.vertex_type);
		gpu.log_errors(#procedure);

		if mesh.index_count > 0 {
			gpu.draw_elephants(current_camera.draw_mode, mesh.index_count, .Unsigned_Int, nil);
		}
		else {
			gpu.draw_arrays(current_camera.draw_mode, 0, mesh.vertex_count);
		}
	}
}



//
// Rendermodes
//

// todo(josh): maybe do a push/pop rendermode kinda thing?

Rendermode :: enum {
    World,
    Unit,
    Pixel,
}

Rendermode_Proc :: #type proc();

rendermode_world :: proc() {
	current_camera.current_rendermode = .World;
}
rendermode_unit :: proc() {
	current_camera.current_rendermode = .Unit;
}
rendermode_pixel :: proc() {
	current_camera.current_rendermode = .Pixel;
}



//
// Helpers
//

create_cube_model :: proc() -> Model {
	indices := []u32 {
		 0,  2,  1,  0,  3,  2,
		 4,  5,  6,  4,  6,  7,
		 8, 10,  9,  8, 11, 10,
		12, 13, 14, 12, 14, 15,
		16, 17, 18, 16, 18, 19,
		20, 22, 21, 20, 23, 22,
	};

    verts := []Vertex3D {
    	{{-0.5, -0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0, -1}},
    	{{ 0.5, -0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0, -1}},
    	{{ 0.5,  0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0, -1}},
    	{{-0.5,  0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0, -1}},

    	{{-0.5, -0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0,  1}},
    	{{ 0.5, -0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0,  1}},
    	{{ 0.5,  0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0,  1}},
    	{{-0.5,  0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  0,  1}},

    	{{-0.5, -0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{-1,  0,  0}},
    	{{-0.5,  0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{-1,  0,  0}},
    	{{-0.5,  0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{-1,  0,  0}},
    	{{-0.5, -0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{-1,  0,  0}},

    	{{ 0.5, -0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 1,  0,  0}},
    	{{ 0.5,  0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 1,  0,  0}},
    	{{ 0.5,  0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 1,  0,  0}},
    	{{ 0.5, -0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 1,  0,  0}},

    	{{-0.5, -0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0, -1,  0}},
    	{{ 0.5, -0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0, -1,  0}},
    	{{ 0.5, -0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0, -1,  0}},
    	{{-0.5, -0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0, -1,  0}},

    	{{-0.5,  0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  1,  0}},
    	{{ 0.5,  0.5, -0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  1,  0}},
    	{{ 0.5,  0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  1,  0}},
    	{{-0.5,  0.5,  0.5}, {}, Colorf{1, 1, 1, 1}, Vec3{ 0,  1,  0}},
    };

    model: Model;
    add_mesh_to_model(&model, verts, indices);
    return model;
}

create_quad_model :: proc() -> Model {
    verts := []Vertex3D {
        {{-0.5, -0.5, 0}, {0, 0, 0}, Colorf{1, 1, 1, 1}, Vec3{0, 0, 1}},
        {{-0.5,  0.5, 0}, {0, 1, 0}, Colorf{1, 1, 1, 1}, Vec3{0, 0, 1}},
        {{ 0.5,  0.5, 0}, {1, 1, 0}, Colorf{1, 1, 1, 1}, Vec3{0, 0, 1}},
        {{ 0.5, -0.5, 0}, {1, 0, 0}, Colorf{1, 1, 1, 1}, Vec3{0, 0, 1}},
    };

    indices := []u32 {
    	0, 2, 1, 0, 3, 2
    };

    model: Model;
    add_mesh_to_model(&model, verts, indices);
    return model;
}

get_mouse_world_position :: proc(camera: ^Camera, cursor_unit_position: Vec2) -> Vec3 {
	cursor_viewport_position := to_vec4((cursor_unit_position * 2) - Vec2{1, 1});
	cursor_viewport_position.w = 1;

	// todo(josh): should probably make this 0.5 because I think directx is 0 -> 1 instead of -1 -> 1 like opengl
	cursor_viewport_position.z = 0.1; // just some way down the frustum

	inv := mat4_inverse_(mul(construct_projection_matrix(camera), construct_view_matrix(camera)));

	cursor_world_position4 := mul(inv, cursor_viewport_position);
	if cursor_world_position4.w != 0 do cursor_world_position4 /= cursor_world_position4.w;
	cursor_world_position := to_vec3(cursor_world_position4);

	return cursor_world_position;
}

get_mouse_direction_from_camera :: proc(camera: ^Camera, cursor_unit_position: Vec2) -> Vec3 {
	if !camera.is_perspective {
		return quaternion_forward(camera.rotation);
	}

	cursor_world_position := get_mouse_world_position(camera, cursor_unit_position);
	cursor_direction := norm(cursor_world_position - camera.position);
	return cursor_direction;
}

world_to_viewport :: proc(position: Vec3, camera: ^Camera) -> Vec3 {
	proj := construct_projection_matrix(camera);
	mv := mul(proj, construct_view_matrix(camera));
	result := mul(mv, Vec4{position.x, position.y, position.z, 1});
	if result.w > 0 do result /= result.w;
	return Vec3{result.x, result.y, result.z};
}
world_to_pixel :: proc(a: Vec3, camera: ^Camera, pixel_width: f32, pixel_height: f32) -> Vec3 {
	result := world_to_viewport(a, camera);
	result = viewport_to_pixel(result, pixel_width, pixel_height);
	return result;
}
world_to_unit :: proc(a: Vec3, camera: ^Camera) -> Vec3 {
	result := world_to_viewport(a, camera);
	result = viewport_to_unit(result);
	return result;
}

unit_to_pixel :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3 {
	result := a * Vec3{pixel_width, pixel_height, 1};
	return result;
}
unit_to_viewport :: proc(a: Vec3) -> Vec3 {
	result := (a * 2) - Vec3{1, 1, 0};
	return result;
}

pixel_to_viewport :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3 {
	a := a;
	a /= Vec3{pixel_width/2, pixel_height/2, 1};
	a -= Vec3{1, 1, 0};
	return a;
}
pixel_to_unit :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3 {
	a := a;
	a /= Vec3{pixel_width, pixel_height, 1};
	return a;
}

viewport_to_pixel :: proc(a: Vec3, pixel_width: f32, pixel_height: f32) -> Vec3 {
	a := a;
	a += Vec3{1, 1, 0};
	a *= Vec3{pixel_width/2, pixel_height/2, 0};
	a.z = 0;
	return a;
}
viewport_to_unit :: proc(a: Vec3) -> Vec3 {
	a := a;
	a += Vec3{1, 1, 0};
	a /= 2;
	a.z = 0;
	return a;
}