package wbml

import rt "core:runtime"
import "core:mem"
import "core:types"

using import "core:strings"
using import "core:fmt"
using import "../laas"

serialize :: proc(value: ^$Type) -> string {
	serialize_one_thing :: proc(name: string, value: rawptr, ti: ^rt.Type_Info, sb: ^Builder, indent_level: int) {
		print_indents :: inline proc(indent_level: int, sb: ^Builder) {
			for i in 0..indent_level-1 {
				sbprint(sb, "\t");
			}
		}

		print_to_buff :: inline proc(sb: ^Builder, args: ..any) {
			sbprint(sb, ..args);
		}

		if name == "_unserialized" {
			indent_level -= 1;
			return;
		}

		if name != "" {
			print_to_buff(sb, name, " ");
		}

		do_newline := true;
		switch kind in ti.variant {
			case rt.Type_Info_Integer: {
				if kind.signed {
					switch ti.size {
						case 1: print_to_buff(sb, (cast(^i8 )value)^);
						case 2: print_to_buff(sb, (cast(^i16)value)^);
						case 4: print_to_buff(sb, (cast(^i32)value)^);
						case 8: print_to_buff(sb, (cast(^i64)value)^);
						case: panic(tprint(ti.size));
					}
				}
				else {
					switch ti.size {
						case 1: print_to_buff(sb, (cast(^u8 )value)^);
						case 2: print_to_buff(sb, (cast(^u16)value)^);
						case 4: print_to_buff(sb, (cast(^u32)value)^);
						case 8: print_to_buff(sb, (cast(^u64)value)^);
						case: panic(tprint(ti.size));
					}
				}
			}

			case rt.Type_Info_Float: {
				switch ti.size {
					case 4: print_to_buff(sb, (cast(^f32)value)^);
					case 8: print_to_buff(sb, (cast(^f64)value)^);
					case: panic(tprint(ti.size));
				}
			}

			case rt.Type_Info_Enum: {
				do_newline = false;

				get_str :: proc(i: $T, e: rt.Type_Info_Enum) -> (string, bool) {
					if types.is_string(e.base) {
						for val, idx in e.values {
							if v, ok := val.(T); ok && v == i {
								return e.names[idx], true;
							}
						}
					} else if len(e.values) == 0 {
						return "", true;
					} else {
						for val, idx in e.values {
							if v, ok := val.(T); ok && v == i {
								return e.names[idx], true;
							}
						}
					}
					return "", false;
				}

				a := any{value, rt.type_info_base(kind.base).id};
				switch v in a {
				case rune:    str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case i8:      str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case i16:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case i32:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case i64:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case int:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case u8:      str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case u16:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case u32:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case u64:     str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case uint:    str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				case uintptr: str, ok := get_str(v, kind); assert(ok); print_to_buff(sb, str);
				}
			}

			case rt.Type_Info_Boolean: {
				print_to_buff(sb, (cast(^bool)value)^);
			}

			case rt.Type_Info_String: {
				if name[0] == '_' do
					print_to_buff(sb, "`", (cast(^string)value)^, "`");
				else do
					print_to_buff(sb, "\"", (cast(^string)value)^, "\"");
			}

			case rt.Type_Info_Named: {
				serialize_one_thing("", value, kind.base, sb, indent_level);
			}
			case rt.Type_Info_Struct: {
				print_to_buff(sb, "{\n"); indent_level += 1;
				for name, idx in kind.names {
					print_indents(indent_level, sb);
					serialize_one_thing(name, mem.ptr_offset(cast(^byte)value, cast(int)kind.offsets[idx]), kind.types[idx], sb, indent_level);
				}
				indent_level -= 1; print_indents(indent_level, sb); print_to_buff(sb, "}");
			}

			case rt.Type_Info_Array: {
				print_to_buff(sb, "[\n"); indent_level += 1;
				{
					for i in 0..kind.count-1 {
						data := mem.ptr_offset(cast(^byte)value, i * kind.elem_size);
						print_indents(indent_level, sb);
						serialize_one_thing("", data, kind.elem, sb, indent_level);
					}
				}
				indent_level -= 1; print_indents(indent_level, sb); print_to_buff(sb, "]");
			}

			case rt.Type_Info_Dynamic_Array: {
				dyn := transmute(^mem.Raw_Dynamic_Array)value;
				print_to_buff(sb, "[\n"); indent_level += 1;
				{
					for i in 0..dyn.len-1 {
						data := mem.ptr_offset(cast(^byte)dyn.data, i * kind.elem_size);
						print_indents(indent_level, sb);
						serialize_one_thing("", data, kind.elem, sb, indent_level);
					}
				}
				indent_level -= 1; print_indents(indent_level, sb); print_to_buff(sb, "]");
			}

			case rt.Type_Info_Slice: {
				slice := transmute(^mem.Raw_Slice)value;
				print_to_buff(sb, "[\n"); indent_level += 1;
				{
					for i in 0..slice.len-1 {
						data := mem.ptr_offset(cast(^byte)slice.data, i * kind.elem_size);
						print_indents(indent_level, sb);
						serialize_one_thing("", data, kind.elem, sb, indent_level);
					}
				}
				indent_level -= 1; print_indents(indent_level, sb); print_to_buff(sb, "]");
			}

			case rt.Type_Info_Map: {
				// TODO support map
			}

			case: panic(tprint(kind));
		}

		if do_newline {
			print_to_buff(sb, "\n");
		}
	}

	sb: Builder;
	ti := type_info_of(Type);
	serialize_one_thing("", value, ti, &sb, 0);

	return to_string(sb);
}

deserialize :: proc{deserialize_to_value, deserialize_into_pointer};

deserialize_to_value :: inline proc($Type: typeid, text: string) -> Type {
	t: Type;
	deserialize_into_pointer(text, &t);
	return t;
}

deserialize_into_pointer :: proc(text: string, ptr: ^$Type) {
	ti := type_info_of(Type);

	_lexer := laas.Lexer{text, 0, 0, 0, nil};
	lexer := &_lexer;

	token: Token;
	ok := get_next_token(lexer, &token);
	if !ok do panic("empty text");

	parse_value(lexer, token, ptr, ti);
}

parse_value :: proc(lexer: ^Lexer, parent_token: Token, data: rawptr, ti: ^rt.Type_Info, is_negative_number := false) {
	if symbol, ok := parent_token.kind.(laas.Symbol); ok {
		if symbol.value == '-' {
			ok := get_next_token(lexer, &parent_token);
			assert(ok, "End of text when expecting negative number");
			parse_value(lexer, parent_token, data, ti, !is_negative_number);
			return;
		}
	}
	switch value_kind in parent_token.kind {
		case laas.Symbol: {
			switch value_kind.value {
				case '{': {
					token: Token;
					for get_next_token(lexer, &token) {

						for get_next_token(lexer, &token) {
							if _, is_newline := token.kind.(laas.New_Line); is_newline do continue;
							else do break;
						}

						if right_curly, ok2 := token.kind.(laas.Symbol); ok2 && right_curly.value == '}' {
							break;
						}

						variable_name, ok2 := token.kind.(laas.Identifier);
						assert(ok2);

						struct_kind: ^rt.Type_Info_Struct;
						field_ptr  : rawptr;
						field_ti   : ^rt.Type_Info;
						switch ti_kind in &ti.variant {
							case rt.Type_Info_Named:  struct_kind = &ti_kind.base.variant.(rt.Type_Info_Struct);
							case rt.Type_Info_Struct: struct_kind = ti_kind;
							case: panic(tprint(ti_kind));
						}
						assert(struct_kind != nil);
						for name, i in struct_kind.names {
							if name == variable_name.value {
								field_ptr = mem.ptr_offset(cast(^byte)data, cast(int)struct_kind.offsets[i]);
								field_ti  = struct_kind.types[i];
								break;
							}
						}
						assert(field_ptr != nil, tprint("couldn't find name ", variable_name.value));

						value_token: Token;
						ok3 := get_next_token(lexer, &value_token); assert(ok3);
						parse_value(lexer, value_token, field_ptr, field_ti);
					}
				}

				case '[': {
					original_ti: ^rt.Type_Info;
					if named, ok := ti.variant.(rt.Type_Info_Named); ok {
						original_ti = ti;
						ti = named.base;
					}

					switch array_kind in ti.variant {
						case rt.Type_Info_Array: {
							num_entries: int;
							for {
								if num_entries > array_kind.count {
									assert(false, "Too many array elements");
								}

								array_value_token: Token;
								ok := get_next_token(lexer, &array_value_token);
								if !ok do assert(false, "End of text from within array");

								if _, is_newline := array_value_token.kind.(laas.New_Line); is_newline do continue;
								defer num_entries += 1;

								if symbol, is_symbol := array_value_token.kind.(laas.Symbol); is_symbol {
									if symbol.value == ']' do break;
								}

								parse_value(lexer, array_value_token, mem.ptr_offset(cast(^byte)data, array_kind.elem_size * num_entries), array_kind.elem);
							}
						}
						case rt.Type_Info_Dynamic_Array: {
							memory := make([]byte, 1024);
							byte_index := 0;

							num_entries: int;
							for {

								array_value_token: Token;
								ok := get_next_token(lexer, &array_value_token);
								if !ok do assert(false, "End of text from within array");

								if _, is_newline := array_value_token.kind.(laas.New_Line); is_newline do continue;
								defer num_entries += 1;

								if symbol, is_symbol := array_value_token.kind.(laas.Symbol); is_symbol {
									if symbol.value == ']' do break;
								}

								// todo(josh): kinda weird that this is a loop, we could probably figure out
								// the size we need to fit things in
								for byte_index + array_kind.elem_size > len(memory) {
									old_mem := memory;
									memory = make([]byte, len(old_mem) * 2);
									mem.copy(&memory[0], &old_mem[0], len(old_mem));
									delete(old_mem);
								}

								parse_value(lexer, array_value_token, &memory[byte_index], array_kind.elem);
								byte_index += array_kind.elem_size;
							}

							(cast(^mem.Raw_Dynamic_Array)data)^ = mem.Raw_Dynamic_Array{&memory[0], num_entries-1, len(memory) / array_kind.elem_size, {}};
						}
						case rt.Type_Info_Slice: {
							memory := make([]byte, 1024);
							byte_index := 0;

							num_entries: int;
							for {

								array_value_token: Token;
								ok := get_next_token(lexer, &array_value_token);
								if !ok do assert(false, "End of text from within array");

								if _, is_newline := array_value_token.kind.(laas.New_Line); is_newline do continue;
								defer num_entries += 1;

								if symbol, is_symbol := array_value_token.kind.(laas.Symbol); is_symbol {
									if symbol.value == ']' do break;
								}

								// todo(josh): kinda weird that this is a loop, we could probably figure out
								// the size we need to fit things in
								for byte_index + array_kind.elem_size > len(memory) {
									old_mem := memory;
									memory = make([]byte, len(old_mem) * 2);
									mem.copy(&memory[0], &old_mem[0], len(old_mem));
									delete(old_mem);
								}

								parse_value(lexer, array_value_token, &memory[byte_index], array_kind.elem);
								byte_index += array_kind.elem_size;
							}

							(cast(^mem.Raw_Slice)data)^ = mem.Raw_Slice{&memory[0], num_entries-1};
						}
						case: panic(tprint("Unhandled case: ", array_kind, "original ti: ", original_ti));
					}
				}

				case: {
					panic(tprint("Unhandled case: ", value_kind.value));
				}
			}
		}

		// primitives
		case laas.String: {
			(cast(^string)data)^ = strings.clone(value_kind.value);
		}

		case laas.Identifier: {
			switch kind in ti.variant {
				case rt.Type_Info_Boolean: {
					switch value_kind.value {
						case "true", "True", "TRUE":    (cast(^bool)data)^ = true;
						case "false", "False", "FALSE": (cast(^bool)data)^ = false;
						case: {
							assert(false, value_kind.value);
						}
					}
				}

				case rt.Type_Info_Named: {
					parse_value(lexer, parent_token, data, kind.base);
				}

				case rt.Type_Info_Enum: {
					get_val_for_name :: proc(name: string, $Type: typeid, e: rt.Type_Info_Enum) -> (Type, bool) {
						for enum_member_name, idx in e.names {
							if enum_member_name == name {
								return e.values[idx].(Type), true;
							}
						}
						return Type{}, false;
					}

					a := any{data, rt.type_info_base(kind.base).id};
					switch v in a {
					case rune:    val, ok := get_val_for_name(value_kind.value, rune,    kind); assert(ok); (cast(^rune)   data)^ = val;
					case i8:      val, ok := get_val_for_name(value_kind.value, i8,      kind); assert(ok); (cast(^i8)     data)^ = val;
					case i16:     val, ok := get_val_for_name(value_kind.value, i16,     kind); assert(ok); (cast(^i16)    data)^ = val;
					case i32:     val, ok := get_val_for_name(value_kind.value, i32,     kind); assert(ok); (cast(^i32)    data)^ = val;
					case i64:     val, ok := get_val_for_name(value_kind.value, i64,     kind); assert(ok); (cast(^i64)    data)^ = val;
					case int:     val, ok := get_val_for_name(value_kind.value, int,     kind); assert(ok); (cast(^int)    data)^ = val;
					case u8:      val, ok := get_val_for_name(value_kind.value, u8,      kind); assert(ok); (cast(^u8)     data)^ = val;
					case u16:     val, ok := get_val_for_name(value_kind.value, u16,     kind); assert(ok); (cast(^u16)    data)^ = val;
					case u32:     val, ok := get_val_for_name(value_kind.value, u32,     kind); assert(ok); (cast(^u32)    data)^ = val;
					case u64:     val, ok := get_val_for_name(value_kind.value, u64,     kind); assert(ok); (cast(^u64)    data)^ = val;
					case uint:    val, ok := get_val_for_name(value_kind.value, uint,    kind); assert(ok); (cast(^uint)   data)^ = val;
					case uintptr: val, ok := get_val_for_name(value_kind.value, uintptr, kind); assert(ok); (cast(^uintptr)data)^ = val;
					}
				}
				case rt.Type_Info_Map: {

				}
				case: {
					assert(false, tprint(kind));
				}
			}
		}

		case laas.Number: {
			sign := is_negative_number ? -1 : 1;
			switch num_kind in ti.variant {
				case rt.Type_Info_Integer: {
					if num_kind.signed {
						switch ti.size {
							case 1: (cast(^i8)data)^  = cast(i8) value_kind.int_value * cast(i8) sign;
							case 2: (cast(^i16)data)^ = cast(i16)value_kind.int_value * cast(i16)sign;
							case 4: (cast(^i32)data)^ = cast(i32)value_kind.int_value * cast(i32)sign;
							case 8: (cast(^i64)data)^ =          value_kind.int_value * cast(i64)sign;
							case: panic(tprint(ti.size));
						}
					}
					else {
						switch ti.size {
							case 1: (cast(^u8)data)^  = cast(u8) value_kind.unsigned_int_value * cast(u8) sign;
							case 2: (cast(^u16)data)^ = cast(u16)value_kind.unsigned_int_value * cast(u16)sign;
							case 4: (cast(^u32)data)^ = cast(u32)value_kind.unsigned_int_value * cast(u32)sign;
							case 8: (cast(^u64)data)^ =          value_kind.unsigned_int_value * cast(u64)sign;
							case: panic(tprint(ti.size));
						}
					}
				}
				case rt.Type_Info_Float: {
					switch ti.size {
						case 4: (cast(^f32)data)^ = cast(f32)value_kind.float_value * cast(f32)sign;
						case 8: (cast(^f64)data)^ =          value_kind.float_value * cast(f64)sign;
						case: panic(tprint(ti.size));
					}
				}
				case rt.Type_Info_Named: {
					parse_value(lexer, parent_token, data, num_kind.base);
				}
				case: {
					assert(false, tprint(num_kind));
				}
			}
		}
	}
}