package workbench

using import        "core:math"
using import        "core:fmt"
      import        "core:os"
      import        "core:mem"

      import odingl "external/gl"
      import stb    "external/stb"
      import ai     "external/assimp"

//
// Textures and sprites
//

ATLAS_DIM :: 2048;
PIXELS_PER_WORLD_UNIT :: 24;

Texture_Atlas :: struct {
	id: Texture,
	atlas_x: i32,
	atlas_y: i32,
	biggest_height: i32,
}

Sprite :: struct {
	uvs:    [4]Vec2,
	width:  f32,
	height: f32,
	id:     Texture,
}

Mesh_Data :: struct {
	vertices: []Vertex3D,
	indicies: []u32,
	name: string,
}

Model_Data :: struct {
	meshes: []Mesh_Data,
}

create_atlas :: inline proc() -> ^Texture_Atlas {
	texture := gen_texture();
	bind_texture2d(texture);
	odingl.TexImage2D(odingl.TEXTURE_2D, 0, odingl.RGBA, ATLAS_DIM, ATLAS_DIM, 0, odingl.RGBA, odingl.UNSIGNED_BYTE, nil);

	data := new_clone(Texture_Atlas{texture, 0, 0, 0});

	return data;
}

destroy_atlas :: inline proc(atlas: ^Texture_Atlas) {
	delete_texture(atlas.id);
	free(atlas);
}

load_sprite :: proc(texture: ^Texture_Atlas, data: []byte) -> (Sprite, bool) {
	stb.set_flip_vertically_on_load(1);
	sprite_width, sprite_height, channels: i32;
	pixel_data := stb.load_from_memory(&data[0], cast(i32)len(data), &sprite_width, &sprite_height, &channels, 0);
	assert(pixel_data != nil);

	defer stb.image_free(pixel_data);

	bind_texture2d(texture.id);

	if texture.atlas_x + sprite_width > ATLAS_DIM {
		texture.atlas_y += texture.biggest_height;
		texture.biggest_height = 0;
		texture.atlas_x = 0;
	}

	if sprite_height > texture.biggest_height do texture.biggest_height = sprite_height;
	odingl.TexSubImage2D(odingl.TEXTURE_2D, 0, texture.atlas_x, texture.atlas_y, sprite_width, sprite_height, odingl.RGBA, odingl.UNSIGNED_BYTE, pixel_data);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_WRAP_S, odingl.MIRRORED_REPEAT);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_WRAP_T, odingl.MIRRORED_REPEAT);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_MIN_FILTER, odingl.NEAREST);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_MAG_FILTER, odingl.NEAREST);
	bottom_left_x := cast(f32)texture.atlas_x / ATLAS_DIM;
	bottom_left_y := cast(f32)texture.atlas_y / ATLAS_DIM;

	width_fraction  := cast(f32)sprite_width / ATLAS_DIM;
	height_fraction := cast(f32)sprite_height / ATLAS_DIM;

	coords := [4]Vec2 {
		{bottom_left_x,                  bottom_left_y},
		{bottom_left_x,                  bottom_left_y + height_fraction},
		{bottom_left_x + width_fraction, bottom_left_y + height_fraction},
		{bottom_left_x + width_fraction, bottom_left_y},
	};

	texture.atlas_x += sprite_width;

	sprite := Sprite{coords, cast(f32)sprite_width / PIXELS_PER_WORLD_UNIT, cast(f32)sprite_height / PIXELS_PER_WORLD_UNIT, texture.id};
	return sprite, true;
}

load_texture :: proc(data: []byte) -> Texture {
	width, height, channels: i32;
	pixel_data := stb.load_from_memory(&data[0], cast(i32)len(data), &width, &height, &channels, 0);
	assert(pixel_data != nil);
	defer stb.image_free(pixel_data);

	tex := gen_texture();
	bind_texture2d(tex);

	odingl.TexImage2D(odingl.TEXTURE_2D, 0, odingl.RGB, width, height, 0, odingl.RGB, odingl.UNSIGNED_BYTE, pixel_data);

	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_MIN_FILTER, odingl.NEAREST);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_MAG_FILTER, odingl.NEAREST);

	return tex;
}

rebuffer_texture :: proc(texture: Texture, new_data: []byte) {
	width, height, channels: i32;
	pixel_data := stb.load_from_memory(&new_data[0], cast(i32)len(new_data), &width, &height, &channels, 0);
	assert(pixel_data != nil);
	defer stb.image_free(pixel_data);

	bind_texture2d(texture);
	odingl.TexImage2D(odingl.TEXTURE_2D, 0, odingl.RGB, width, height, 0, odingl.RGB, odingl.UNSIGNED_BYTE, pixel_data);
}

release_texture :: proc(texture: Texture) {
	delete_texture(texture);
}

load_model_from_memory :: proc(data: []byte) -> Model_Data {
	pHint : byte;
	scene := ai.import_file_from_memory(&data[0], i32(len(data)),
		cast(u32) ai.aiPostProcessSteps.CalcTangentSpace |
		cast(u32) ai.aiPostProcessSteps.Triangulate |
		cast(u32) ai.aiPostProcessSteps.JoinIdenticalVertices |
		cast(u32) ai.aiPostProcessSteps.SortByPType |
		cast(u32) ai.aiPostProcessSteps.FlipWindingOrder|
		cast(u32) ai.aiPostProcessSteps.FlipUVs, &pHint);
	assert(scene != nil, tprint(ai.get_error_string()));
	defer ai.release_import(scene);

	return _load_model_internal(scene);
}

load_model_from_file :: proc(path: cstring) -> Model_Data {
	scene := ai.import_file(path,
		cast(u32) ai.aiPostProcessSteps.CalcTangentSpace |
		cast(u32) ai.aiPostProcessSteps.Triangulate |
		cast(u32) ai.aiPostProcessSteps.JoinIdenticalVertices |
		cast(u32) ai.aiPostProcessSteps.SortByPType |
		cast(u32) ai.aiPostProcessSteps.FlipWindingOrder|
		cast(u32) ai.aiPostProcessSteps.FlipUVs);
	assert(scene != nil, tprint(ai.get_error_string()));
	defer ai.release_import(scene);

	return _load_model_internal(scene);
}

_load_model_internal :: proc(scene: ^ai.aiScene) -> Model_Data {
	mesh_count := cast(int) scene.mNumMeshes;
	meshes_processed := make([dynamic]Mesh_Data, 0, mesh_count);

	meshes := mem.slice_ptr(scene^.mMeshes, cast(int) scene.mNumMeshes);
	for _, i in meshes // iterate meshes in scene
	{
		mesh := meshes[i];

		verts := mem.slice_ptr(mesh.mVertices, cast(int) mesh.mNumVertices);
		norms := mem.slice_ptr(mesh.mNormals, cast(int) mesh.mNumVertices);

		colours : []ai.aiColor4D;
		if mesh.mColors[0] != nil do
			colours = mem.slice_ptr(mesh.mColors[0], cast(int) mesh.mNumVertices);

		texture_coords : []ai.aiVector3D;
		if mesh.mTextureCoords[0] != nil do
			texture_coords = mem.slice_ptr(mesh.mTextureCoords[0], cast(int) mesh.mNumVertices);

		processedVerts := make([dynamic]Vertex3D, 0, mesh.mNumVertices);

		// process vertices into Vertex3D struct
		// TODO (jake): support vertex colours
		for i in 0 .. mesh.mNumVertices - 1
		{
			normal := norms[i];
			position := verts[i];

			colour: Colorf;
			if mesh.mColors[0] != nil do
				colour = Colorf(colours[i]);
			else
			{
				rnd := (cast(f32)i / cast(f32)len(verts)) * 0.75 + 0.25;
				colour = Colorf{rnd, 0, rnd, 1};
			}

			texture_coord: Vec3;
			if mesh.mTextureCoords[0] != nil do
				texture_coord = Vec3{texture_coords[i].x, texture_coords[i].y, texture_coords[i].z};
			else do
				texture_coord = Vec3{0, 0, 0};

			vert := Vertex3D{
				Vec3{position.x, position.y, position.z},
				texture_coord,
				colour,
				Vec3{normal.x, normal.y, normal.z}};

			append(&processedVerts, vert);
		}

		indicies := make([dynamic]u32, 0, mesh.mNumVertices);

		faces := mem.slice_ptr(mesh.mFaces, cast(int) mesh.mNumFaces);
		// iterate all faces, build Index array
		for i in 0 .. mesh.mNumFaces-1
		{
			face := faces[i];
			faceIndicies := mem.slice_ptr(face.mIndices, cast(int) face.mNumIndices);
			for j in 0 .. face.mNumIndices-1
			{
				append(&indicies, faceIndicies[j]);
			}
		}

		// create mesh
		append(&meshes_processed, Mesh_Data{
			processedVerts[:],
			indicies[:],
			string(mesh.mName.data[:mesh.mName.length])
		});
	}

	// return all created meshIds
	return Model_Data{meshes_processed[:]};
}

release_model :: proc(model: Model) {
	for mesh in model.meshes {
		release_mesh(mesh);
	}
}

//
// Fonts
//

Font :: struct {
	dim: int,
	size: f32,
	chars: []stb.Baked_Char,
	id: Texture,
}

font_default: ^Font;

load_font :: proc(data: []byte, size: f32) -> (^Font, bool) {
	pixels: []u8;
	chars:  []stb.Baked_Char;
	dim := 128;

	// @InfiniteLoop
	for {
		pixels = make([]u8, dim * dim);
		ret: int;
		chars, ret = stb.bake_font_bitmap(data, 0, size, pixels, dim, dim, 0, 128);
		if ret < 0 {
			delete(pixels);
			dim *= 2;
		}
		else {
			break;
		}
	}

	texture := gen_texture();
	bind_texture2d(texture);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_MIN_FILTER, odingl.LINEAR);
	odingl.TexParameteri(odingl.TEXTURE_2D, odingl.TEXTURE_MAG_FILTER, odingl.LINEAR);
	odingl.TexImage2D(odingl.TEXTURE_2D, 0, odingl.RGBA, cast(i32)dim, cast(i32)dim, 0, odingl.RED, odingl.UNSIGNED_BYTE, &pixels[0]);

	font := new_clone(Font{dim, size, chars, texture});
	return font, true;
}

destroy_font :: inline proc(font: ^Font) {
	delete(font.chars);
	delete_texture(font.id);
	free(font);
}