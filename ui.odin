package workbench

import rt "core:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:os"
import "core:sort"

import "logging"
import "basic"
import "types"
import "math"
import "platform"
import "wbml"
import "gpu"

import "external/imgui"

UIID :: u64;

UI_Rect :: struct {
	id: UIID,
	layer: int,
	serial: int,
	x1, y1: f32, // top left pixel
	x2, y2: f32, // bottom right pixel
}

uiid :: proc(loc: rt.Source_Code_Location, extra := "") -> UIID {
	id := loc.hash;
	return combine_id(id, extra);
}

combine_id :: proc(id: u64, extra: string) -> UIID {
	id := id;
	for b in extra {
		id = (id * 0x100000001b3) ~ u64(id);
	}
	return id;
}

UI_Manager :: struct {
	hovered: UIID,
	active: UIID,

	current_rect: UI_Rect,
	current_serial: int,

	current_layer: int,

	rects_last_frame: [dynamic]UI_Rect,
	rects_this_frame: [dynamic]UI_Rect,
}

ui_manager: UI_Manager;

update_ui :: proc(dt: f32) {
	using ui_manager;

	rects_last_frame, rects_this_frame = rects_this_frame, rects_last_frame;

	sort.quick_sort_proc(rects_last_frame[:], proc(a, b: UI_Rect) -> int {
		if a.layer != b.layer {
			return a.layer - b.layer;
		}
		return a.serial - b.serial;
	});

	hovered = 0;
	for i := len(rects_last_frame)-1; i >= 0; i -= 1 {
		rect := rects_last_frame[i];
		if mouse_in_rect(rect) {
			hovered = rect.id;
			break;
		}
	}

	clear(&rects_this_frame);

	current_serial = 0;
	current_rect = UI_Rect{uiid(#location(), "hjakshfjkasf"), 0, current_serial, 0, 0, platform.main_window.width, platform.main_window.height};
	current_serial = 1;
}

@(deferred_out=pop_rect)
PUSH_RECT :: proc(x1, y1, x2, y2: f32, top : f32 = 0, right : f32 = 0, bottom : f32 = 0, left : f32 = 0, layer := 0, id := "", loc := #caller_location) -> UI_Rect {
	return push_rect_non_deferred(x1, y1, x2, y2, top, right, bottom, left, layer, id, loc);
}

push_rect_non_deferred :: proc(unitx1, unity1, unitx2, unity2: f32, top : f32 = 0, right : f32 = 0, bottom : f32 = 0, left : f32 = 0, layer := 0, id := "", loc := #caller_location) -> UI_Rect {
	using ui_manager;

	old := current_rect;
	current_serial += 1;
	id := uiid(loc, id);

	cw := current_rect.x2 - current_rect.x1;
	ch := current_rect.y2 - current_rect.y1;
	x1 := current_rect.x1 + cw * unitx1 + left;
	y1 := current_rect.y1 + ch * unity1 + top;
	x2 := current_rect.x1 + cw * unitx2 - right;
	y2 := current_rect.y1 + ch * unity2 - bottom;

	current_rect = UI_Rect{id, layer, current_serial, x1, y1, x2, y2};
	append(&rects_this_frame, current_rect);
	return old;
}

pop_rect :: proc(old: UI_Rect) {
	ui_manager.current_rect = old;
}

Button_State :: enum {
	None,     // mouse is not interacting with the button at all
	Hovered,  // mouse is over button
	Pressed,  // mouse is currently pressed down
	Clicked,  // mouse was just released while the cursor was in the bounds of the button
	Released, // mouse was just released while the cursor was outside the bounds of the button
}

button_behaviour :: proc() -> Button_State {
	using ui_manager;

	id := current_rect.id;

	if platform.get_input_up(.Mouse_Left) {
		if active == id {
			if hovered == id {
				active = 0;
				return .Clicked;
			}
			else {
				active = 0;
				return .Released;
			}
		}
	}
	else if platform.get_input_down(.Mouse_Left) {
		if hovered == id {
			active = id;
			return .Pressed;
		}
	}
	else if platform.get_input(.Mouse_Left) {
		if active == id {
			return .Pressed;
		}
	}
	else {
		if hovered == id {
			return .Hovered;
		}
	}

	return .None;
}

mouse_in_rect :: proc(rect: UI_Rect) -> bool {
	x, y := expand_to_tuple(platform.main_window.mouse_position_pixel);
	y = platform.main_window.height - y;
	return x >= rect.x1 && x <= rect.x2 && y >= rect.y1 && y <= rect.y2;
}

colored_rect :: proc(color: Colorf) {
	using ui_manager;

	im_quad(.Pixel, get_shader("default"), Vec2{current_rect.x1, current_rect.y1}, Vec2{current_rect.x2, current_rect.y2}, color, {});
}

button :: proc(str: string, font: Font, loc := #caller_location) -> bool {
	using ui_manager;

	PUSH_RECT(0, 0, 1, 1, 0, 0, 0, 0, current_layer, str, loc);

	state := button_behaviour();
    switch state {
        case .None:     colored_rect(Colorf{.2, .2, .2, 1});
        case .Released: colored_rect(Colorf{.2, .2, .2, 1});

        case .Clicked:  colored_rect(Colorf{.3, .3, .3, 1});
        case .Hovered:  colored_rect(Colorf{.3, .3, .3, 1});

        case .Pressed:  colored_rect(Colorf{.4, .4, .4, 1});

        case: panic(tprint(state));
    }

    textpos := Vec2{lerp(cast(f32)current_rect.x1, cast(f32)current_rect.x2, f32(0.5)), current_rect.y2};

	height_of_rect : f32 = current_rect.y2 - current_rect.y1;
    sz := height_of_rect / font.pixel_height;

    str_width := get_string_width(.Pixel, font, str, sz);
    textpos.x -= str_width * 0.5; // center on X
    textpos.y -= height_of_rect * 0.2; // @Hack center on Y. fonts seem to have a lot of headroom in font.pixel_height, so we just nudge it up by some amount

    im_text(.Pixel, font, str, textpos, Colorf{1, 1, 1, 1}, sz);

    return state == .Clicked;
}

ui_text_edit_buffer: [1024]byte;

text_input :: proc(str: ^string, id: string = "", loc := #caller_location) -> bool {
	using ui_manager;

	// id := uiid(loc, id);
	// if active != id {

	// }

	// // button part
	// PUSH_RECT(0, 0, 1, 1, 0, 0, 0, 0, current_layer, id, loc);
	// // current_rect.id = combine_id(current_rect.id, "joasfhjklasuhfjaklf");
	// state := button_behaviour();
	// logln(state);
	// colored_rect(Colorf{0, 1, 0, 1});

	// text part
	// PUSH_RECT(0, 0, 1, 1, 0, 0, 0, 0, current_layer, id, loc);
	// current_rect.id = combine_id(current_rect.id, "uioyuiywiehwjkk");
	// if state == .Clicked {
	// 	logln("clicked!");
	// 	active = current_rect.id;
	// }

	// if active == current_rect.id {
	// 	logln("active");
	// 	if platform.get_input_down(.Enter) {
	// 		active = 0;
	// 		return true;
	// 	}
	// }

	return false;
}

Vertical_Layout :: struct {
	old: UI_Rect,
	element_pixel_height: f32,
	num_things: int,
}

vl_begin :: proc(element_pixel_height: f32) -> Vertical_Layout {
	old := push_rect_non_deferred(0, 0, 1, 0, 0, 0, -element_pixel_height, 0);
	vl := Vertical_Layout{old, element_pixel_height, 0};
	return vl;
}

vl_next :: proc(vl: ^Vertical_Layout) {
	using vl;
	pop_rect(old);
	vl.num_things += 1;
	push_rect_non_deferred(0, 0, 1, 0, element_pixel_height*cast(f32)vl.num_things, 0, -element_pixel_height*(cast(f32)vl.num_things+1), 0);
}

vl_end :: proc(vl: ^Vertical_Layout) {
	pop_rect(vl.old);
}














when false {

//
// API
//

// Rects

IMGUI_Rect :: struct {
	imgui_id:  IMGUI_ID,
	kind: IMGUI_Rect_Kind,
	code_line: string, // note(josh): not set for items in the system, only set right before drawing the UI debug window
	location: rt.Source_Code_Location,

	unit_rect: Unit_Rect,
	pixel_rect: Pixel_Rect,

	unit_param_x1, unit_param_y1, unit_param_x2, unit_param_y2: f32,
	pixel_param_top, pixel_param_right, pixel_param_bottom, pixel_param_left: int,
}

IMGUI_Rect_Kind :: enum {
	Push_Rect,
	Draw_Colored_Quad,
	Draw_Sprite,
	Button,
	Fit_To_Aspect,
	Scroll_View,
	Text,
}

ui_push_rect :: proc(x1, y1, x2, y2: f32, _top := 0, _right := 0, _bottom := 0, _left := 0, rect_kind := IMGUI_Rect_Kind.Push_Rect, loc := #caller_location, pivot := Vec2{0.5, 0.5}) -> IMGUI_Rect {
	top    := _top;
	right  := _right;
	bottom := _bottom;
	left   := _left;
	if len(ui_rect_stack) > 0 && basic.last(ui_rect_stack[:]).kind == IMGUI_Rect_Kind.Scroll_View {
		top    -= cast(int)(current_scroll_view.scroll_offset.y);
		right  -= cast(int)(current_scroll_view.scroll_offset.x);
		bottom += cast(int)(current_scroll_view.scroll_offset.y);
		left   += cast(int)(current_scroll_view.scroll_offset.x);
	}

	current_rect: Unit_Rect;
	if len(ui_rect_stack) == 0 {
		current_rect = Unit_Rect{0, 0, 1, 1};
	}
	else {
		current_rect = ui_current_rect_unit;
	}

	cur_w := current_rect.x2 - current_rect.x1;
	cur_h := current_rect.y2 - current_rect.y1;

	cww := cast(f32)platform.main_window.width;
	cwh := cast(f32)platform.main_window.height;

	new_x1 := current_rect.x1 + (cur_w * x1) + ((cast(f32)left   / cww));
	new_y1 := current_rect.y1 + (cur_h * y1) + ((cast(f32)bottom / cwh));

	new_x2 := current_rect.x2 - cast(f32)cur_w * (1-x2) - ((cast(f32)right / cww));
	new_y2 := current_rect.y2 - cast(f32)cur_h * (1-y2) - ((cast(f32)top   / cwh));

	ui_current_rect_unit = Unit_Rect{new_x1, new_y1, new_x2, new_y2};
	ui_current_rect_pixels = Pixel_Rect{cast(int)(ui_current_rect_unit.x1 * cww), cast(int)(ui_current_rect_unit.y1 * cwh), cast(int)(ui_current_rect_unit.x2 * cww), cast(int)(ui_current_rect_unit.y2 * cwh)};

	rect := IMGUI_Rect{get_imgui_id_from_location(loc), rect_kind, "", loc, ui_current_rect_unit, ui_current_rect_pixels, x1, y1, x2, y2, top, right, bottom, left};
	append(&ui_rect_stack, rect);
	append(&new_imgui_rects, rect);

	if current_scroll_view != nil {
		r := &current_scroll_view.total_rect;
		r.x1 = min(r.x1, ui_current_rect_pixels.x1);
		r.y1 = min(r.y1, ui_current_rect_pixels.y1);
		r.x2 = max(r.x2, ui_current_rect_pixels.x2);
		r.y2 = max(r.y2, ui_current_rect_pixels.y2);
	}

	return rect;
}

ui_pop_rect :: proc(loc := #caller_location) -> IMGUI_Rect {
	popped_rect := pop(&ui_rect_stack);
	rect := ui_rect_stack[len(ui_rect_stack)-1];
	ui_current_rect_pixels = rect.pixel_rect;
	ui_current_rect_unit = rect.unit_rect;
	return popped_rect;
}

// Drawing

ui_draw_colored_quad :: proc{ui_draw_colored_quad_current, ui_draw_colored_quad_push};
ui_draw_colored_quad_current :: inline proc(color: Colorf) {
	rect := ui_current_rect_pixels;
	min := Vec2{cast(f32)rect.x1, cast(f32)rect.y1};
	max := Vec2{cast(f32)rect.x2, cast(f32)rect.y2};
	im_quad(.Pixel, get_shader("default"), min, max, color, Texture{});
}
ui_draw_colored_quad_push :: inline proc(color: Colorf, x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, IMGUI_Rect_Kind.Draw_Colored_Quad, loc);
	ui_draw_colored_quad(color);
	ui_pop_rect(loc);
}

ui_draw_sprite :: proc{ui_draw_sprite_current, ui_draw_sprite_push, ui_draw_sprite_default};
ui_draw_sprite_default :: proc(sprite: Sprite, loc := #caller_location) {
	ui_draw_sprite_current(sprite, get_shader("default"), loc);
}
ui_draw_sprite_current :: proc(sprite: Sprite, shader: gpu.Shader_Program, loc := #caller_location) {
	rect := ui_current_rect_pixels;
	min := Vec2{cast(f32)rect.x1, cast(f32)rect.y1};
	max := Vec2{cast(f32)rect.x2, cast(f32)rect.y2};
	im_sprite_minmax(.Pixel, shader, min, max, sprite.uvs, sprite.id);
}
ui_draw_sprite_current_decomp :: proc(uvs: [4]Vec2, id: Texture, shader: gpu.Shader_Program, loc := #caller_location) {
	rect := ui_current_rect_pixels;
	min := Vec2{cast(f32)rect.x1, cast(f32)rect.y1};
	max := Vec2{cast(f32)rect.x2, cast(f32)rect.y2};
	im_sprite_minmax(.Pixel, shader, min, max, uvs, id);
}
ui_draw_sprite_push :: inline proc(sprite: Sprite, x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, IMGUI_Rect_Kind.Draw_Sprite, loc);
	ui_draw_sprite_default(sprite, loc);
	ui_pop_rect(loc);
}
ui_draw_sprite_push_decomp :: inline proc(uvs: [4]Vec2, id: Texture, x1, y1, x2, y2: f32, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, IMGUI_Rect_Kind.Draw_Sprite, loc);
	ui_draw_sprite_current_decomp(uvs, id, get_shader("default"), loc);
	ui_pop_rect(loc);
}

ui_draw_sliced_sprite :: proc(sprite: Sprite, loc := #caller_location) {
	rect := ui_current_rect_pixels;
	min := Vec2{cast(f32)rect.x1, cast(f32)rect.y1};
	max := Vec2{cast(f32)rect.x2, cast(f32)rect.y2};

	sprite := sprite;
	slice_info, ok := getval(&sprite.slice_info);
	assert(ok, "Cannot draw sliced sprite. No slice info.", loc);

	x1 := slice_info.slice_min.x / f32(rect.x2 - rect.x1);
	y1 := slice_info.slice_min.y / f32(rect.y2 - rect.y1);
	x2 := 1 - slice_info.slice_max.x / f32(rect.x2 - rect.x1);
	y2 := 1 - slice_info.slice_max.y / f32(rect.y2 - rect.y1);

	ui_draw_sprite_push_decomp(slice_info.uvs[0], sprite.id,  0,  0, x1, y1);
	ui_draw_sprite_push_decomp(slice_info.uvs[1], sprite.id,  0, y1, x1, y2);
	ui_draw_sprite_push_decomp(slice_info.uvs[2], sprite.id,  0, y2, x1,  1);

	ui_draw_sprite_push_decomp(slice_info.uvs[3], sprite.id, x1,  0, x2, y1);
	ui_draw_sprite_push_decomp(slice_info.uvs[4], sprite.id, x1, y1, x2, y2);
	ui_draw_sprite_push_decomp(slice_info.uvs[5], sprite.id, x1, y2, x2,  1);

	ui_draw_sprite_push_decomp(slice_info.uvs[6], sprite.id,  x2,  0,  1, y1);
	ui_draw_sprite_push_decomp(slice_info.uvs[7], sprite.id,  x2, y1,  1, y2);
	ui_draw_sprite_push_decomp(slice_info.uvs[8], sprite.id,  x2, y2,  1,  1);
}

// Text

Text_Visuals :: struct {
	size: f32,
	color: Colorf,
	center: bool,
	fit_to_rect: bool,

	using shadow_params: struct {
		shadow: int, // in pixels, 0 for none
		shadow_color: Colorf,
	},
}

Text_Data :: struct {
	font: Font,
	size: f32,
	color: Colorf,

	using shadow_params: struct {
		shadow: int, // in pixels, 0 for none
		shadow_color: Colorf,
	},

	center: b64,

	push_new_rect: bool,
	x1, y1, x2, y2: f32,
	top, right, bottom, left: int,
}

ui_text :: proc{ui_text_data, ui_text_args};
ui_text_data :: proc(str: string, font: Font, visuals: Text_Visuals, loc := #caller_location) {
	// if push_new_rect {
	// 	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, IMGUI_Rect_Kind.Text, loc);
	// }
	// defer if push_new_rect do ui_pop_rect(loc);

	position := Vec2{ui_current_rect_unit.x1, ui_current_rect_unit.y1};
	current_height := (ui_current_rect_unit.y2 - ui_current_rect_unit.y1) * platform.main_window.height / font.pixel_height * visuals.size;

	text_height := current_height;

	if visuals.fit_to_rect {
		text_width := im_text(.Unit, font, str, position, visuals.color, text_height, current_render_layer, false);
		current_width  := f32(ui_current_rect_pixels.x2 - ui_current_rect_pixels.x1);
		text_height = min(current_height, (current_width / text_width / platform.main_window.width) * current_height);
	}

	if visuals.center {
		ww := get_string_width(.Unit, font, str, text_height);
		rect_width  := (ui_current_rect_unit.x2 - ui_current_rect_unit.x1);
		rect_height := (ui_current_rect_unit.y2 - ui_current_rect_unit.y1);

		// text_size_to_rect := (font.pixel_height * size / (rect_height * main_window.height));
		// logln(text_size_to_rect);

		position = Vec2{ui_current_rect_unit.x1 + (rect_width  / 2) - ww/2,
						// ui_current_rect_unit.y1 + (rect_height / 2) - (text_size_to_rect)};
						ui_current_rect_unit.y1};
	}

	if visuals.shadow != 0 {
		im_text(.Unit, font, str, position+Vec2{cast(f32)visuals.shadow/platform.main_window.width, cast(f32)-visuals.shadow/platform.main_window.width}, visuals.shadow_color, text_height); // todo(josh): @TextRenderOrder: proper render order on text
	}

	im_text(.Unit, font, str, position, visuals.color, text_height); // todo(josh): @TextRenderOrder: proper render order on text
}
ui_text_args :: proc(font: Font, str: string, size: f32, color: Colorf, x1 := cast(f32)0, y1 := cast(f32)0, x2 := cast(f32)1, y2 := cast(f32)1, top := 0, right := 0, bottom := 0, left := 0, loc := #caller_location) {
	ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, IMGUI_Rect_Kind.Text, loc);
	defer ui_pop_rect(loc);

	position := Vec2{cast(f32)ui_current_rect_unit.x1, cast(f32)ui_current_rect_unit.y1};
	height := (ui_current_rect_unit.y2 - ui_current_rect_unit.y1) * cast(f32)platform.main_window.height / font.pixel_height;

	im_text(.Unit, font, str, position, color, height * size); // todo(josh): @TextRenderOrder: proper render order on text
}

// Buttons

Button_Data :: struct {
	x1, y1, x2, y2: f32,
	top, right, bottom, left: int,

	on_hover:    proc(button: ^Button_Data),
	on_pressed:  proc(button: ^Button_Data),
	on_released: proc(button: ^Button_Data),
	on_clicked:  proc(button: ^Button_Data),

	color: Colorf,
	pressed: bool,
}

ui_default_button :: proc() -> Button_Data {
	return Button_Data{0, 0, 1, 1, 0, 0, 0, 0, nil, nil, nil, nil, Colorf{1, 1, 1, 1}, false};
}

ui_button :: proc(using button: ^Button_Data, str: string = "", font: Font = {}, visuals: Text_Visuals = {}, loc := #caller_location) -> bool {

	rect := ui_push_rect(x1, y1, x2, y2, top, right, bottom, left, IMGUI_Rect_Kind.Button, loc);
	defer ui_pop_rect(loc);

	mouse_in := ui_current_contains_mouse();

	// Draw button stuff
	ui_draw_colored_quad(color);

	// Draw text stuff
	if str != "" {
		ui_text(str, font, visuals, loc);
	}

	// were we recently pressed and are now releasing?
	if pressed && platform.get_input_up(.Mouse_Left) {
		pressed = false;
		if mouse_in do
			if on_clicked != nil do button.on_clicked(button);
		if on_released != nil do button.on_released(button);
		return true;
	}

	// pressing
	if mouse_in && platform.get_input_down(.Mouse_Left) {
		pressed = true;
		if on_pressed != nil do button.on_pressed(button);
	}

	// hover. mayber else if?
	if mouse_in {
		if on_hover != nil do button.on_hover(button);
	}

	return false;
}

// ui_button_click :: proc(using button: ^Button_Data) {
// 	clicked = frame_count;
// }

// Aspect Ratio Fitter

Aspect_Ratio_Fit_Kind :: enum {
	Current_Rect,
	Height_Determines_Width,
	Width_Determines_Height,
}

ui_aspect_ratio_fitter :: proc(ww, hh: f32, fit_type: Aspect_Ratio_Fit_Kind = .Current_Rect, loc := #caller_location) {
	current_rect_width_unit  : f32 = (ui_current_rect_unit.x2 - ui_current_rect_unit.x1);
	current_rect_height_unit : f32 = (ui_current_rect_unit.y2 - ui_current_rect_unit.y1);

	assert(current_rect_height_unit != 0);
	current_rect_aspect : f32 = (current_rect_height_unit * platform.main_window.height) / (current_rect_width_unit * platform.main_window.width);

	aspect : f32 = hh / ww;
	width:   f32;
	height:  f32;
	switch fit_type {
		case .Current_Rect: {
			if aspect < current_rect_aspect {
				width  = current_rect_height_unit;
				height = current_rect_height_unit * aspect;
			}
			else {
				aspect = ww / hh;
				height = current_rect_height_unit;
				width  = current_rect_height_unit * aspect;
			}
		}
		case .Height_Determines_Width: {
			aspect = ww / hh;
			height = current_rect_height_unit;
			width  = current_rect_height_unit * aspect;
		}
		case .Width_Determines_Height: {
			width  = current_rect_height_unit;
			height = current_rect_height_unit * aspect;
		}
	}

	h_width  := cast(int)round(platform.main_window.height * width  / 2);
	h_height := cast(int)round(platform.main_window.height * height / 2);

	ui_push_rect(0.5, 0.5, 0.5, 0.5, -h_height, -h_width, -h_height, -h_width, IMGUI_Rect_Kind.Fit_To_Aspect, loc);
}

ui_end_aspect_ratio_fitter :: proc(loc := #caller_location) {
	ui_pop_rect(loc);
}

// Scroll View

Scroll_View_Kind :: enum {
	Vertical,
	Horizontal,
	Both,
}

ui_start_scroll_view :: proc(scroll_speed: f32, kind := Scroll_View_Kind.Vertical, loc := #caller_location) {
	assert(current_scroll_view == nil, "no nested scroll views!");

	// scroll view id
	{
		id := get_imgui_id_from_location(loc);
		current_scroll_view_id = id;
		ok: bool;
		_current_scroll_view, ok = all_scroll_views[id];
		if !ok do _current_scroll_view.total_rect = ui_current_rect_pixels;
	}

	svv := _current_scroll_view;

	size := Vec2{cast(f32)svv.total_rect.x2 - cast(f32)svv.total_rect.x1, cast(f32)svv.total_rect.y2 - cast(f32)svv.total_rect.y1};

	rect := ui_push_rect(0, 0, 1, 1, 0, 0, 0, 0, IMGUI_Rect_Kind.Scroll_View, loc);

	current_scroll_view = &_current_scroll_view;
	sv := current_scroll_view;

	if hot == rect.imgui_id {
		if platform.get_input_down(.Mouse_Left) {
			sv.scroll_at_pressed_position = sv.scroll_offset_target;
		}

		// if get_mouse(Mouse.Left) {
		// 	if abs(mouse_position_pixel.y - cursor_pixel_position_on_clicked.y) > 0.005 {
		// 		hot = id;
		// 	}
		// }

		offset := sv.scroll_at_pressed_position - (cursor_pixel_position_on_clicked - platform.main_window.mouse_position_pixel);
		switch kind {
			case .Vertical:   sv.scroll_offset_target.y = offset.y;
			case .Horizontal: sv.scroll_offset_target.x = offset.x;
			case .Both:       sv.scroll_offset_target   = offset;
		}
	}
	else {
		clamp :: inline proc(a: ^f32, min, max: f32) {
			if a^ < min do a^ = min;
			if a^ > max do a^ = max;
		}

		clamp(&sv.scroll_offset_target.y, 0, cast(f32)-sv.total_rect.y1-(cast(f32)ui_current_rect_pixels.y2-cast(f32)ui_current_rect_pixels.y1));
	}

	if warm == rect.imgui_id {
		sv.scroll_offset_target.y -= platform.main_window.mouse_scroll * 50;
	}

	sv.scroll_offset = lerp(sv.scroll_offset, sv.scroll_offset_target, scroll_speed);
}

ui_end_scroll_view :: proc(loc := #caller_location) {
	all_scroll_views[current_scroll_view_id] = current_scroll_view^;
	current_scroll_view = nil;
	ui_pop_rect(loc);
}

// Grids

Grid_Layout :: struct {
	// user vars
	element_index: int,
	max: int,
	progress01: f32,

	// wb vars
	ww, hh: int,
	cur_x, cur_y: int,

	pushed_rect: bool,
}

ui_grid_layout :: proc(ww, hh: int) -> Grid_Layout {
	if ww == 0 || hh == 0 do return {};

	grid := Grid_Layout{-1, ww * hh, 0.0, ww, hh, -1, 0, false};
	ui_grid_layout_next(&grid);
	return grid;
}

ui_grid_layout_next :: proc(using grid: ^Grid_Layout) -> bool {
	if ww == 0 || hh == 0 do return false;
	if element_index >= max do return false;

	if cur_x != -1 {
		ui_pop_rect();
		pushed_rect = false;
	}

	cur_x += 1;
	if cur_x >= ww {
		cur_x = 0;
		cur_y += 1;
	}

	www := 1.0/f32(ww);
	hhh := 1.0/f32(hh);
	x1 := www*f32(cur_x);
	y1 := hhh*f32(hh - cur_y - 1);

	ui_push_rect(x1, y1, x1 + www, y1 + hhh);
	pushed_rect = true;

	element_index += 1;
	progress01 = cast(f32)element_index / cast(f32)max;
	return element_index < max;
}

ui_grid_layout_end :: proc(grid: ^Grid_Layout) {
	if grid.pushed_rect do ui_pop_rect();
}

ui_current_contains_mouse :: proc() -> bool {
	if len(ui_rect_stack) == 0 do return false;

	return platform.main_window.mouse_position_pixel.x >= f32(ui_current_rect_pixels.x1) &&
		   platform.main_window.mouse_position_pixel.y >= f32(ui_current_rect_pixels.y1) &&
		   platform.main_window.mouse_position_pixel.x <= f32(ui_current_rect_pixels.x2) &&
		   platform.main_window.mouse_position_pixel.y <= f32(ui_current_rect_pixels.y2);
}

// Directional Layout Groups

// Directional_Layout_Group :: struct {
// 	x1, y1, x2, y2: f32,
// 	origin: Vec2,
// 	direction: Vec2,
// 	using _: struct { // runtime fields
// 		num_items_so_far: int,
// 	},
// }

// direction_layout_group_next :: proc(dlg: ^Directional_Layout_Group) {
// 	rect := ui_pop_rect();
// }

// UI Specs
// todo(josh): do UI specs

UI_Spec :: struct {
	commands: [dynamic]UI_Command,
	allocator: mem.Allocator `wbml_noserialize`,
}

UI_Command :: struct {
	name: string,
	kind: union {
		UI_Command_Push_Rect,
		UI_Command_Text,
		UI_Command_Draw_Color,
		UI_Command_Grid_Layout,
	},
	children: [dynamic]UI_Command `imgui_hidden`,
}

UI_Command_Push_Rect :: struct {
	x1, y1, x2, y2: f32,
	top, right, bottom, left: int `imgui_allow64bit`,
}

UI_Command_Text :: struct {
	text: string,
	visuals: Text_Visuals,
}

UI_Command_Draw_Color :: struct {
	color: Colorf,
}

UI_Command_Grid_Layout :: struct {
	width, height: int `imgui_allow64bit`,
}

// ui_spec_from_wbml :: proc(wbml_data: string) -> UI_Spec {
	// return UI_Spec{wbml.deserialize([]UI_Command, wbml_data)};
// }

// ui_delete_ui_spec :: proc(spec: ^UI_Spec) {

// }


//
// Internal
//

Rect :: struct(kind: typeid) {
	x1, y1, x2, y2: kind,
}

Pixel_Rect :: Rect(int);
Unit_Rect  :: Rect(f32);

ui_rect_stack:   [dynamic]IMGUI_Rect;
all_imgui_rects: [dynamic]IMGUI_Rect;
new_imgui_rects: [dynamic]IMGUI_Rect;
ui_current_rect_unit:   Unit_Rect;
ui_current_rect_pixels: Pixel_Rect;

IMGUI_ID :: int;
id_counts: map[string]int;

hot:     IMGUI_ID = -1;
warm:    IMGUI_ID = -1;
previously_hot:  IMGUI_ID = -1;
previously_warm: IMGUI_ID = -1;
cursor_pixel_position_on_clicked: Vec2;

Scroll_View :: struct {
	total_rect: Pixel_Rect,
	scroll_at_pressed_position: Vec2,
	scroll_offset: Vec2,
	scroll_offset_target: Vec2,
}

all_scroll_views: map[IMGUI_ID]Scroll_View;
_current_scroll_view: Scroll_View;
current_scroll_view_id: IMGUI_ID;
current_scroll_view: ^Scroll_View;

UI_Debug_File_Line :: struct {
	file_path: string,
	line: int,
	text: string,
}

ui_debug_cur_idx: int;
debugging_ui: bool;
all_ui_debug_file_lines: [dynamic]UI_Debug_File_Line;

update_ui :: proc() {
	mouse_in_rect :: inline proc(unit_rect: Rect(f32)) -> bool {
		cursor_in_rect := platform.main_window.mouse_position_unit.y < unit_rect.y2 &&
		                  platform.main_window.mouse_position_unit.y > unit_rect.y1 &&
		                  platform.main_window.mouse_position_unit.x < unit_rect.x2 &&
		                  platform.main_window.mouse_position_unit.x > unit_rect.x1;
		return cursor_in_rect;
	}

	previously_hot = -1;
	if platform.get_input_up(.Left) {
		if hot != -1 {
			previously_hot = hot;
			hot = -1;
		}
	}

	previously_warm = -1;
	old_warm := warm;
	warm = -1;
	i := len(all_imgui_rects)-1;
	for i >= 0 {
		can_be_hot_or_warm :: inline proc(kind: IMGUI_Rect_Kind) -> bool {
			using IMGUI_Rect_Kind;
			switch kind {
				case Button, Scroll_View: return true;
				case Push_Rect, Text, Draw_Colored_Quad, Draw_Sprite, Fit_To_Aspect: return false;
				case: panic(tprint("Unsupported kind: ", kind));
			}
			return false;
		}

		defer i -= 1;
		rect := &all_imgui_rects[i];

		if can_be_hot_or_warm(rect.kind) {
			if warm == -1 {
				if mouse_in_rect(rect.unit_rect) {
					warm = rect.imgui_id;
				}
			}

			if warm == rect.imgui_id {
				if platform.get_input_down(.Mouse_Left) {
					hot = rect.imgui_id;
					cursor_pixel_position_on_clicked = platform.main_window.mouse_position_pixel;
				}
			}
		}
	}

	if warm != old_warm {
		previously_warm = old_warm;
	}

	clear(&id_counts);
	assert(len(ui_rect_stack) == 0 || len(ui_rect_stack) == 1);
	clear(&ui_rect_stack);
	clear(&new_imgui_rects);
	ui_current_rect_pixels = Pixel_Rect{};
	ui_current_rect_unit = Unit_Rect{};

	ui_push_rect(0, 0, 1, 1, 0, 0, 0, 0);
}

late_update_ui :: proc() {
	all_imgui_rects, new_imgui_rects = new_imgui_rects, all_imgui_rects;
	clear(&new_imgui_rects);

	if debugging_ui {
		if imgui.begin("UI System") {
			if len(all_imgui_rects) > 0 {
				UI_Debug_Info :: struct {
					pushed_rects: i32,
				};

				debug := UI_Debug_Info{cast(i32)len(all_imgui_rects)};
				imgui_struct(&debug, "ui_debug_info");
				rect := all_imgui_rects[ui_debug_cur_idx];
				assert(rect.code_line == "");
				text, ok := ui_debug_get_file_line(rect.location.file_path, rect.location.line);
				rect.code_line = basic.trim_whitespace(text);

				imgui_struct(&rect, "ui_element");

				for rect, i in all_imgui_rects {
					if ui_debug_cur_idx == i {
						imgui.bullet();
					}
					if imgui.small_button(fmt.tprintf("%s##%d", basic.pretty_location(rect.location), i)) {
						ui_debug_cur_idx = i;
					}

					if ui_debug_cur_idx == i {
						min := Vec2{cast(f32)rect.pixel_rect.x1, cast(f32)rect.pixel_rect.y1};
						max := Vec2{cast(f32)rect.pixel_rect.x2, cast(f32)rect.pixel_rect.y2};
						// push_debug_box(rendermode_pixel, to_vec3(min), to_vec3(max), COLOR_GREEN);

						ui_push_rect(0, 0.05, 1, 0.15);
						defer ui_pop_rect();
					}
				}
			}
		}

		imgui.end();
	}
}

// todo(josh): use Source_Code_Location.hash and a hashmap probably. this is so old

Location_ID_Mapping :: struct {
	id: IMGUI_ID,
	using loc: rt.Source_Code_Location,
	index: int,
}

all_imgui_mappings: [dynamic]Location_ID_Mapping;

get_imgui_id_from_location :: proc(loc: rt.Source_Code_Location, loc2 := #caller_location) -> IMGUI_ID {
	count, ok := id_counts[loc.file_path];
	if !ok {
		id_counts[loc.file_path] = 0;
		count = 0;
	}
	else {
		count += 1;
		id_counts[loc.file_path] = count;
	}

	for val, idx in all_imgui_mappings {
		if val.line      != loc.line      do continue;
		if val.column    != loc.column    do continue;
		if val.index     != count         do continue;
		if val.file_path != loc.file_path do continue;
		return val.id;
	}

	id := len(all_imgui_mappings);
	mapping := Location_ID_Mapping{id, loc, count};
	append(&all_imgui_mappings, mapping);
	return mapping.id;
}

// UI debug information

ui_debug_get_file_line :: proc(file_path: string, line: int) -> (string, bool) {
	for fl in all_ui_debug_file_lines {
		if fl.line == line && fl.file_path == file_path do return fl.text, true;
	}
	data, ok := os.read_entire_file(file_path);
	if !ok {
		return "", false;
	}
	defer delete(data);

	cur_line := 1;
	line_start := -1;
	for b, i in data {
		if b == '\n' {
			cur_line += 1;
			if cur_line == line {
				line_start = i;
			}
			else if cur_line == line + 1 {
				text := strings.clone(cast(string)data[line_start:i]);
				fl := UI_Debug_File_Line{file_path, line, text};
				append(&all_ui_debug_file_lines, fl);
				return text, true;
			}
		}
	}
	return "", false;
}

}
